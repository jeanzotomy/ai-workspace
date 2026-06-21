# AI Workspace — Guide d'intégration (glue entre les briques)

> Ce document explique en détail comment les briques de l'AI Workspace communiquent
> entre elles. Lire après le déploiement initial (`make up`).

---

## Table des matières

1. [Dify → Langfuse (OpenTelemetry)](#1-dify--langfuse-opentelemetry)
2. [Infisical → services (injection de secrets)](#2-infisical--services-injection-de-secrets)
3. [SSO Authentik — flux OIDC et forwardAuth](#3-sso-authentik--flux-oidc-et-forwardauth)
4. [Open WebUI → Dify (API OpenAI-compatible)](#4-open-webui--dify-api-openai-compatible)
5. [Comp AI → Langfuse (audit trails)](#5-comp-ai--langfuse-audit-trails)

---

## 1. Dify → Langfuse (OpenTelemetry)

### Comment ça marche

Dify trace nativement ses appels LLM via OpenTelemetry (depuis Dify v1.0+).
Langfuse v3 expose un endpoint OTLP HTTP (`/api/public/otel`) qui reçoit ces traces.
La configuration se fait **par application** dans l'UI Dify — pas globalement.

### Prérequis

1. Langfuse est démarré et accessible à `https://observe.${DOMAIN}`
2. Créer un projet Langfuse et générer des clés API :
   - Se connecter à Langfuse
   - Settings > API Keys > Create new key
   - Noter `public_key` et `secret_key`
3. Mettre à jour `.env` :
   ```
   LANGFUSE_PUBLIC_KEY=pk-lf-xxxxxxxxxxxx
   ```

### Configuration dans Dify (par application)

Pour **chaque application** que vous voulez tracer :

1. Ouvrir l'application dans Dify (`https://dify.${DOMAIN}`)
2. Aller dans **Monitoring** (icône graphe dans la barre de gauche)
3. Cliquer **Add** > choisir **Langfuse**
4. Remplir :
   - **Host** : `https://observe.${DOMAIN}` (URL publique Langfuse)
     - En interne (réseau aiws) : `http://langfuse-web:3000` est aussi possible si Dify ne peut pas accéder à l'URL publique
   - **Public Key** : valeur de `LANGFUSE_PUBLIC_KEY`
   - **Secret Key** : valeur de la secret key Langfuse
5. Cliquer **Test** → doit afficher "Connected"
6. Activer le toggle Langfuse

### Vérification d'une trace

Après avoir exécuté un chat ou workflow dans l'application Dify :

1. Ouvrir Langfuse (`https://observe.${DOMAIN}`)
2. Aller dans **Traces**
3. Une trace doit apparaître avec les spans LLM (modèle, tokens, coût, durée)

### Variables d'env alternatives (global)

Si vous souhaitez un tracing global (toutes les apps Dify) sans passer par l'UI,
ajoutez dans `.env` et dans le bloc `x-dify-common-env` de `compose/dify.yml` :

```env
# À ajouter dans compose/dify.yml → x-dify-common-env si tracing global souhaité
OPENTELEMETRY_ENABLED=true
OPENTELEMETRY_EXPORTER_OTLP_TRACES_ENDPOINT=http://langfuse-web:3000/api/public/otel/v1/traces
OPENTELEMETRY_EXPORTER_OTLP_TRACES_HEADERS=Authorization=Basic <base64(pk:sk)>
```

Générer le header Base64 :
```bash
echo -n "pk-lf-xxx:sk-lf-xxx" | base64
```

---

## 2. Infisical → services (injection de secrets)

### Stratégie recommandée

En **développement** : les secrets sont dans `.env` (généré par bootstrap.sh).
En **production** : les clés API LLM (OpenAI, Anthropic, Mistral) sont stockées dans
Infisical et injectées dans les services sans jamais toucher `.env`.

### Pourquoi ne pas tout mettre dans .env en prod

- `.env` est sur le disque du serveur — risque en cas d'accès non autorisé
- Infisical chiffre les secrets au repos + audit log de chaque accès
- Rotation possible sans redéployer les conteneurs

### Configuration initiale d'Infisical

1. Se connecter à `https://secrets.${DOMAIN}`
2. Créer une organisation et un projet `ai-workspace`
3. Créer les secrets dans l'environnement `production` :
   ```
   OPENAI_API_KEY      = sk-...
   ANTHROPIC_API_KEY   = sk-ant-...
   MISTRAL_API_KEY     = ...
   AZURE_OPENAI_API_KEY = ...
   ```
4. Créer une **Machine Identity** pour l'injection :
   - Settings > Machine Identities > Create
   - Nom : `ai-workspace-injector`
   - Donner accès `read` au projet `ai-workspace`
   - Générer un **Client ID** et **Client Secret**

### Injection via `infisical run` (recommandé)

Au lieu de `docker compose up`, utiliser :

```bash
# Installer Infisical CLI
curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | bash
apt install infisical

# Login avec la machine identity
export INFISICAL_TOKEN=$(infisical login \
    --method=universal-auth \
    --client-id="${INFISICAL_CLIENT_ID}" \
    --client-secret="${INFISICAL_CLIENT_SECRET}" \
    --plain \
    --silent)

# Démarrer les services avec injection des secrets
infisical run \
    --projectId="${INFISICAL_PROJECT_ID}" \
    --env=production \
    --path=/ai-workspace \
    -- docker compose up -d
```

### Injection via Infisical Agent (sidecar avancé)

Pour les cas où les services ont besoin des secrets au runtime (pas au démarrage) :

```yaml
# À ajouter comme service dans docker-compose.yml
  infisical-agent:
    image: infisical/cli:latest
    container_name: infisical-agent
    command: agent
    environment:
      INFISICAL_TOKEN: ${INFISICAL_AGENT_TOKEN}
    volumes:
      - ./config/infisical/agent.yaml:/etc/infisical/agent.yaml:ro
      - secrets_volume:/run/secrets
    networks:
      - aiws
```

### Exemple concret : Dify consommant les clés LLM depuis Infisical

```bash
# Wrapper de démarrage qui injecte les secrets LLM dans l'env de dify-api
OPENAI_API_KEY="$(infisical secrets get OPENAI_API_KEY --plain --env=production)"
export OPENAI_API_KEY

docker compose -f compose/dify.yml up -d dify-api dify-worker
```

Ou, plus élégamment, configurer les clés LLM **directement dans l'UI Dify** :
- Settings > Model Providers > OpenAI > API Key = valeur récupérée depuis Infisical
- Ce mode évite de passer les clés par des variables d'env des conteneurs

---

## 3. SSO Authentik — flux OIDC et forwardAuth

### Flux OIDC (Open WebUI, Langfuse, Comp AI)

```
Navigateur       Authentik              Application
    │                │                      │
    │── GET /login ──►│                      │
    │                 │── redirect ──────────►│
    │                 │                      │
    │── GET auth.${DOMAIN}/... ──────────────────►│ (Authentik)
    │                 │                      │
    │   [login form]  │                      │
    │── POST credentials ──────────────────►│ (Authentik)
    │                 │                      │
    │◄── redirect to app /callback ──────────│
    │                 │                      │
    │── GET /callback?code=... ────────────────────►│
    │                 │                      │
    │                 │◄── POST token exchange ──────│
    │                 │                      │
    │                 │── JWT id_token ──────►│
    │                 │                      │
    │◄────── Session créée, accès accordé ──────────│
```

### Appliquer le blueprint

1. Se connecter à `https://auth.${DOMAIN}` avec le compte admin bootstrap
2. Admin Interface > Customisation > Blueprints
3. Le blueprint `ai-workspace` doit apparaître dans la liste
4. Cliquer "Apply" — les providers et applications sont créés
5. Pour chaque provider OIDC (Open WebUI, Langfuse, Comp AI) :
   - Admin > Applications > Providers > cliquer sur le provider
   - Copier le **Client ID** et **Client Secret**
   - Reporter dans `.env`

### Variables à reporter après le blueprint

| Variable `.env` | Où trouver dans Authentik |
|---|---|
| `OPENWEBUI_OIDC_CLIENT_ID` | Provider "provider-open-webui" > Client ID |
| `OPENWEBUI_OIDC_CLIENT_SECRET` | Provider "provider-open-webui" > Client Secret |
| `LANGFUSE_OIDC_CLIENT_ID` | Provider "provider-langfuse" > Client ID |
| `LANGFUSE_OIDC_CLIENT_SECRET` | Provider "provider-langfuse" > Client Secret |
| `COMPAI_OIDC_CLIENT_ID` | Provider "provider-comp-ai" > Client ID |
| `COMPAI_OIDC_CLIENT_SECRET` | Provider "provider-comp-ai" > Client Secret |

Après mise à jour de `.env`, redémarrer les services concernés :
```bash
docker compose restart open-webui langfuse-web langfuse-worker comp-ai
```

### ForwardAuth (Dify, Infisical, Traefik dashboard)

Ces services utilisent le mécanisme Traefik + Authentik forwardAuth :

1. Traefik intercepte chaque requête vers `dify.${DOMAIN}` ou `secrets.${DOMAIN}`
2. Il interroge l'outpost Authentik intégré (`/outpost.goauthentik.io/`)
3. Si non authentifié → redirect vers la page de login Authentik
4. Après login → redirect vers l'application originale

Le middleware est défini dans `proxy/dynamic/authentik.yml` (créé par devops-A).

**Limite importante** : le forwardAuth protège l'accès à l'interface, mais
ne propage pas l'identité dans Dify/Infisical. Les utilisateurs voient le login
Authentik puis doivent créer un compte séparé dans Dify/Infisical.
Pour un SSO complet sur Dify et Infisical : éditions entreprise requises.

---

## 4. Open WebUI → Dify (API OpenAI-compatible)

### Comment ça marche

Dify expose chaque application créée comme un endpoint API OpenAI-compatible :
```
POST https://dify.${DOMAIN}/v1/chat/completions
Authorization: Bearer <DIFY_API_KEY>
```

Open WebUI peut consommer cet endpoint comme un modèle.

### Configuration

1. Dans Dify, créer une application de type "Chatbot" ou "Agent"
2. Publier l'application
3. Dans l'application Dify : API Access > copier l'API Key
4. Mettre à jour `.env` : `DIFY_API_KEY=app-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
5. Dans Open WebUI :
   - Settings > Connections > OpenAI API
   - URL : `https://dify.${DOMAIN}/v1` (ou `http://dify-nginx:80/v1` en interne)
   - API Key : valeur de `DIFY_API_KEY`
   - Sauvegarder
6. Les modèles Dify apparaissent dans la liste des modèles Open WebUI

### Configuration via variables d'env (automatique)

Dans `compose/open-webui.yml`, les variables suivantes sont utilisées :
```yaml
OPENAI_API_BASE_URL: "http://dify-nginx:80/v1"
OPENAI_API_KEY: "${DIFY_API_KEY}"
```

Cela configure Open WebUI automatiquement au démarrage.

---

## 5. Comp AI → Langfuse (audit trails)

### Export des traces LLM vers Comp AI

Comp AI peut recevoir les audit trails des appels LLM pour les besoins de conformité
SOC 2 / ISO 27001 / RGPD.

### Mécanisme

1. Langfuse génère des exports de traces (Batch Exports)
2. Comp AI les ingère pour constituer des preuves de conformité

### Activation du batch export Langfuse

Dans `.env` :
```env
LANGFUSE_S3_BATCH_EXPORT_ENABLED=true
```

Puis dans l'UI Langfuse :
- Settings > Batch Exports > Configure
- Le bucket `langfuse` sur MinIO reçoit les exports JSON

### Import dans Comp AI

Dans l'UI Comp AI (`https://compliance.${DOMAIN}`) :
1. Aller dans **Evidence** > **Add Evidence**
2. Source : **S3/MinIO** (configurer avec les creds MinIO)
3. Bucket : `langfuse`, préfixe : `exports/`
4. Associer aux contrôles concernés (ex: "Logging and Monitoring", "Data Processing Records")

### RGPD — Données des traces

Les traces Langfuse peuvent contenir des données personnelles (prompts des utilisateurs).
S'assurer que :
- La rétention est configurée dans Langfuse (Settings > Data Retention)
- Les exports vers Comp AI sont anonymisés si nécessaire (post-traitement)
- Le consentement des utilisateurs est obtenu (mention dans les CGU)
