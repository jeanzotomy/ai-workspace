# AI Workspace — Contrat d'architecture (source de vérité)

> **Ce document est le contrat.** Tout fichier `compose/*.yml`, config proxy, script
> ou portail DOIT respecter exactement les noms, réseaux, ports et conventions ci-dessous.
> En cas de doute, ce document prime. Aucune valeur en dur hors de ce contrat.

---

## 1. Topologie

```
                          Internet (HTTPS 443)
                                  │
                          ┌───────▼────────┐
                          │    Traefik     │  reverse proxy + TLS ACME
                          │  (edge router) │  + forwardAuth → Authentik
                          └───────┬────────┘
        ┌──────────┬──────────┬───┴────┬───────────┬────────────┐
        │          │          │        │           │            │
   ${DOMAIN}   chat.    dify.   observe.   secrets.   compliance.  auth.
   (portal)  OpenWebUI  Dify    Langfuse   Infisical   Comp AI    Authentik
        │          │          │        │           │            │
        └──────────┴──────────┴────────┴───────────┴────────────┘
                          réseau docker: aiws (bridge)
        ┌─────────────── infra partagée (réseau aiws) ───────────────┐
        │  postgres (multi-db)  ·  redis  ·  minio (S3)               │
        │  clickhouse (Langfuse)  ·  qdrant (Dify vector store)       │
        └─────────────────────────────────────────────────────────────┘
```

---

## 2. Réseau & domaines

- **Réseau docker unique** : `aiws` (driver bridge, déclaré une seule fois, `name: aiws`).
- **Domaine de base** : variable `DOMAIN` (ex. `ai.example.com`). En dev local : `aiws.localhost`.
- **Email ACME** : variable `ACME_EMAIL` (Let's Encrypt).

### Table des sous-domaines (routage Traefik)

| Sous-domaine | Service | Conteneur(s) cible | Port interne | Auth |
|---|---|---|---|---|
| `${DOMAIN}` (racine) | Portail | `portal` | 80 | publique |
| `chat.${DOMAIN}` | Open WebUI | `open-webui` | 8080 | OIDC natif |
| `dify.${DOMAIN}` | Dify | `dify-nginx` | 80 | app + forwardAuth |
| `observe.${DOMAIN}` | Langfuse | `langfuse-web` | 3000 | OIDC natif |
| `secrets.${DOMAIN}` | Infisical | `infisical` | 8080 | app (OIDC=enterprise) |
| `compliance.${DOMAIN}` | Comp AI | `comp-ai` | 3000 | OIDC/OAuth |
| `auth.${DOMAIN}` | Authentik | `authentik-server` | 9000 | IdP lui-même |
| `traefik.${DOMAIN}` | Dashboard Traefik | `traefik` | 8080 | forwardAuth |

---

## 3. Noms de conteneurs (IMMUABLES — référencés partout)

```
traefik              authentik-server   authentik-worker
portal               open-webui
dify-api  dify-worker  dify-web  dify-nginx  dify-sandbox  dify-ssrf-proxy
langfuse-web  langfuse-worker
infisical
comp-ai
# infra partagée
postgres   redis   minio   clickhouse   qdrant
```

> Chaque brique OSS lourde (Dify, Langfuse) est isolée dans son propre fichier
> `compose/<brique>.yml` inclus par le `docker-compose.yml` racine via `include:`.

---

## 4. Infra partagée (mutualisation = valeur produit)

Un seul jeu de bases de données à sauvegarder/superviser.

| Service | Image (à confirmer version courante) | Rôle | Consommé par |
|---|---|---|---|
| `postgres` | `postgres:16-alpine` | SGBD multi-bases | Dify, Langfuse, Infisical, Comp AI, Authentik |
| `redis` | `redis:7-alpine` | cache / files | Dify, Langfuse, Infisical, Authentik |
| `minio` | `minio/minio` | stockage S3 | Langfuse (events/media), Dify (uploads) |
| `clickhouse` | `clickhouse/clickhouse-server` | analytics traces | Langfuse v3 |
| `qdrant` | `qdrant/qdrant` | vector store | Dify (RAG) |

### Bases Postgres créées au bootstrap (script init multi-db)
`dify`, `langfuse`, `infisical`, `compai`, `authentik` — chacune avec son user dédié.
Script : `scripts/init-multi-db.sh` (monté dans `/docker-entrypoint-initdb.d/`).

> ⚠️ Si une brique exige une version Postgres incompatible, la sortir en base
> dédiée et le **documenter explicitement** (pas de contournement silencieux).

---

## 5. Conventions de variables d'environnement

- **Tout** dans `.env` (gitignoré). `.env.example` documente chaque variable (jamais de secret réel).
- Préfixe par brique : `DIFY_*`, `LANGFUSE_*`, `INFISICAL_*`, `COMPAI_*`, `AUTHENTIK_*`, `OPENWEBUI_*`.
- Globales : `DOMAIN`, `ACME_EMAIL`, `TZ`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`,
  `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `CLICKHOUSE_PASSWORD`.
- Secrets générés au bootstrap (jamais commités) : clés de chiffrement, secrets de session,
  paires de clés OIDC. Voir `scripts/bootstrap.sh`.
- **Clés API LLM** (OpenAI/Anthropic/Mistral) : NE PAS mettre dans `.env` en prod →
  gérées par **Infisical** et injectées (voir `docs/INTEGRATION.md`). En dev, fallback `.env`.

---

## 6. Matrice SSO (honnête sur les limites)

Authentik = IdP OIDC. État réel du support OIDC par brique (à valider sur versions courantes) :

| Brique | OIDC natif | Stratégie |
|---|---|---|
| Open WebUI | ✅ | `OAUTH_*` / `OPENID_PROVIDER_URL` → Authentik |
| Langfuse | ✅ | `AUTH_CUSTOM_*` (OIDC custom) → Authentik |
| Comp AI | ✅ (OAuth) | provider OAuth → Authentik |
| Dify | ⚠️ partiel (OIDC = édition entreprise) | login natif + **Traefik forwardAuth** devant la console |
| Infisical | ⚠️ OIDC/SAML = tier payant | login natif + **Traefik forwardAuth** devant l'UI |

> **Règle « no silent caps »** : documenter clairement dans le README que le SSO
> complet sur Dify/Infisical nécessite leurs éditions entreprise ; la suite fournit
> un forward-auth comme garde-fou périmétrique en attendant.

---

## 7. Arborescence du dépôt (qui produit quoi)

```
ai-workspace/
├── docker-compose.yml          # racine : include + réseau aiws + infra partagée   [devops-A]
├── .env.example                # toutes les variables documentées                  [devops-A]
├── compose/
│   ├── infra.yml               # postgres, redis, minio, clickhouse, qdrant        [devops-A]
│   ├── traefik.yml             # reverse proxy + ACME + middlewares                [devops-A]
│   ├── authentik.yml           # IdP (server + worker)                             [devops-A]
│   ├── dify.yml                # api, worker, web, nginx, sandbox, ssrf-proxy      [devops-A]
│   ├── open-webui.yml          # open-webui                                        [devops-A]
│   ├── langfuse.yml            # web + worker                                      [devops-A]
│   ├── infisical.yml           # infisical                                         [devops-A]
│   └── comp-ai.yml             # comp-ai                                           [devops-A]
├── proxy/
│   └── dynamic/                # config dynamique Traefik (middlewares, forwardAuth)[devops-A]
├── config/
│   └── authentik/              # blueprints Authentik (providers/apps OIDC)        [devops-B]
├── scripts/
│   ├── bootstrap.sh            # génère secrets, .env, init                        [devops-B]
│   ├── init-multi-db.sh        # crée les bases postgres                           [devops-B]
│   └── healthcheck.sh          # statut agrégé des services                        [devops-B]
├── portal/                     # page d'accueil unifiée (statique)                 [ux-ui]
│   ├── index.html
│   ├── styles.css
│   └── Dockerfile              # nginx:alpine sert le statique
├── docs/
│   ├── FEATURES.md             # ✅ écrit
│   ├── ARCHITECTURE.md         # ✅ ce fichier
│   ├── INTEGRATION.md          # glue détaillée (OTel, Infisical, SSO)             [devops-B]
│   ├── DEPLOYMENT.md           # guide déploiement VM self-host + local            [devops-B]
│   └── COMMERCIAL.md           # offre, pricing, go-to-market                      [docs]
├── Makefile                    # up/down/logs/bootstrap/health                     [devops-A]
├── README.md                   # vue d'ensemble + quickstart                       [docs]
├── LICENSE
└── .gitignore                  # .env, volumes, secrets
```

---

## 8. Principes non négociables (rappel CLAUDE.md)

1. **Zéro valeur en dur** — URLs, secrets, IDs → variables d'env / `.env`.
2. Tout secret réel hors git ; `.env.example` documente sans exposer.
3. Versions d'images **épinglées** (pas `:latest` en prod) — confirmer les tags courants via la doc officielle de chaque brique.
4. `docker compose config` doit valider sans erreur avant tout commit.
5. Signaler explicitement toute limite (SSO entreprise, version incompatible) — jamais de contournement silencieux.

---

## 9. Versions de référence à confirmer (chaque agent vérifie la doc officielle)

| Brique | Source officielle |
|---|---|
| Dify | `langgenius/dify` → `docker/docker-compose.yaml` |
| Open WebUI | `open-webui/open-webui` (ghcr.io) |
| Langfuse | `langfuse/langfuse` (self-host v3 docker-compose) |
| Infisical | `Infisical/infisical` (self-host docker-compose) |
| Comp AI | `trycompai/comp` (self-host) |
| Authentik | `goauthentik/authentik` (docker-compose) |
| Traefik | `traefik:v3` |

> Ne PAS inventer la structure interne d'une brique : récupérer le compose officiel,
> l'adapter au réseau `aiws` + infra partagée + labels Traefik, et épingler les versions.
