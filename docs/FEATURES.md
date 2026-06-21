# AI Workspace d'Entreprise — Inventaire fonctionnel

> Suite IA **self-hosted** complète : interfaces LLM, orchestration, observabilité,
> conformité et sécurité des secrets. Alternative RGPD-native à
> **Azure OpenAI Studio + Datadog LLM**, déployable via un seul `docker-compose`.
>
> **Cible :** ESN, départements IT entreprise, intégrateurs IA, gouvernements,
> banques UEMOA, universités, ministères (Afrique francophone et au-delà).

---

## 1. Composants (5 briques OSS + 2 briques d'intégration)

| Rôle | Brique | Type | Fonction |
|---|---|---|---|
| **Orchestration IA** | **Dify** | Core | Pipelines RAG, agents, workflows visuels, app builder, API |
| **Interface utilisateur** | **Open WebUI** | Core | Chat frontend pour modèles locaux/cloud |
| **Observabilité LLM** | **Langfuse** | Core | Traces, coûts tokens, évaluations qualité, datasets |
| **Secrets & credentials** | **Infisical** | Support | Clés API LLM, variables d'env sécurisées, rotation |
| **Conformité & audit** | **Comp AI** | Optionnel | SOC 2, ISO 27001, RGPD pour offres IA |
| **SSO / Identité** | **Authentik** | Intégration | Fournisseur OIDC unique pour toute la suite |
| **Reverse proxy / TLS** | **Traefik** | Intégration | Routage sous-domaines, HTTPS auto (Let's Encrypt), forward-auth |
| **Portail d'entrée** | **AI Workspace Portal** | Intégration | Page d'accueil unifiée, cartes services, statut santé, branding |

---

## 2. Fonctionnalités par brique

### 2.1 Dify — Orchestration IA (Core)
- Création d'applications LLM : chatbot, agent, workflow, completion, chatflow
- Pipelines **RAG** : ingestion documents, chunking, embeddings, retrieval
- **Workflows visuels** (nœuds : LLM, knowledge retrieval, code, HTTP, conditions, itérations)
- Agents avec **tool use** (function calling, plugins, MCP)
- Multi-modèles : OpenAI, Anthropic, Mistral, Azure OpenAI, Ollama (local), etc.
- API OpenAI-compatible exposée par app → consommée par Open WebUI et apps tierces
- Gestion des datasets / bases de connaissances (vector store)
- **Intégration native Langfuse** (monitoring par app)

### 2.2 Open WebUI — Interface utilisateur (Core)
- Chat multi-modèles (modèles locaux Ollama + endpoints OpenAI-compatible)
- **Backend = Dify** (Dify exposé comme API OpenAI-compatible)
- RAG côté UI (upload documents, web search)
- Gestion utilisateurs, rôles, groupes
- **SSO OIDC** (via Authentik)
- Multilingue (dont français)

### 2.3 Langfuse — Observabilité LLM (Core)
- **Traces** : chaque prompt / réponse / span / génération
- **Coûts** : calcul automatique des tokens et du coût par modèle
- **Évaluations** : scores qualité (LLM-as-judge, human annotation, datasets)
- Branchement natif sur Dify via **OpenTelemetry** — tracing automatique
- Prompt management, versioning, A/B
- **SSO OIDC** (via Authentik)
- Export des audit trails vers Comp AI

### 2.4 Infisical — Secrets & credentials (Support)
- Stockage chiffré des **clés API LLM** (OpenAI, Anthropic, Mistral…)
- Injection des secrets dans les services **sans jamais les coder en dur**
  (Infisical Agent / CLI `infisical run` / SDK Python·Node)
- Environnements (dev / staging / prod), versioning, rotation
- Audit log d'accès aux secrets
- Intégrations CI/CD

### 2.5 Comp AI — Conformité & audit (Optionnel)
- Frameworks : **SOC 2 Type II, ISO 27001, RGPD**
- Collecte de preuves, registre des contrôles, tâches de conformité
- Audit trail des accès et actions IA (alimenté par Langfuse)
- Politiques, gestion des risques, vendor management

### 2.6 Authentik — SSO / Identité (Intégration)
- Fournisseur **OIDC** unique pour toute la suite
- Connexion unique (login une fois → accès à toutes les interfaces qui supportent OIDC)
- MFA, politiques de mot de passe, groupes → mapping rôles applicatifs
- Forward-auth Traefik pour les UIs sans OIDC natif

### 2.7 Traefik — Reverse proxy / TLS (Intégration)
- Routage par sous-domaine (`chat.`, `dify.`, `observe.`, `secrets.`, `compliance.`, `auth.`)
- **HTTPS automatique** (Let's Encrypt / ACME)
- Middleware forward-auth (Authentik) pour protéger les UIs internes
- Dashboard protégé, redirections, en-têtes de sécurité

### 2.8 Portail d'entrée — AI Workspace Portal (Intégration)
- Page d'accueil unique listant tous les services (cartes cliquables)
- Indicateur de **statut santé** par service (healthcheck agrégé)
- Branding configurable (logo, couleurs, nom de l'organisation)
- Liens documentation et support

---

## 3. Différenciateur clé

> **Langfuse se branche nativement sur Dify via OpenTelemetry** — chaque prompt,
> token et coût est tracé automatiquement. **Infisical gère les clés API**
> (OpenAI, Anthropic, Mistral) sans jamais les stocker en dur. La combinaison
> donne une offre **« IA d'entreprise RGPD-native »** inégalable par les solutions
> cloud — **données 100 % locales**, **coût ~10× moins cher** qu'Azure OpenAI managé.

---

## 4. Intégrations techniques (glue)

| Intégration | Mécanisme |
|---|---|
| Dify → Langfuse | `LANGFUSE_HOST` + clés publiques/secrètes (config par app Dify + env) |
| Infisical → tous les services | Injection secrets via SDK / `infisical run` / Agent (jamais en dur) |
| Open WebUI → Dify | Dify exposé comme backend API OpenAI-compatible |
| Comp AI → Langfuse | Audit trails LLM exportés |
| SSO | Authentik OIDC → Open WebUI, Langfuse, Comp AI (Dify/Infisical : voir limites) |
| Déploiement | **Un seul `docker-compose` orchestre tout** (réseau + proxy partagés) |

---

## 5. Offre commerciale suggérée

| Plan | Prix | Inclus |
|---|---|---|
| **Starter** | 499 €/mois | 5 users, 1M tokens/mois |
| **Business** | 1 499 €/mois | 25 users, 10M tokens/mois |
| **Enterprise** | 4 999 €/mois | Illimité + support dédié |
| **Setup one-time** | 2k–8k € | Selon personnalisation |
| **Formation équipes IA** | 1k–3k €/session | — |

**Métriques cibles :** setup 3k–8k € · opérationnel 400–900 €/mois · lancement 6–10 sem.
· revenu cible 15k–80k €/mois · break-even mois 4–6 (avec 5+ clients).

---

## 6. Opportunité Afrique spécifique

- **Gouvernements** : IA souveraine (données locales, pas de cloud étranger)
- **Banques UEMOA** : analyse documents, KYC automatisé
- **Universités** : assistant pédagogique en langues locales
- **Ministères** : résumé documents officiels, traduction
- **Coût 10× moins cher** que Azure OpenAI managé

---

## 7. Périmètre de CE dépôt (décision 2026-06-21)

✅ **Inclus** : couche d'intégration + packaging — `docker-compose` unifié des 5 OSS,
reverse-proxy Traefik + SSO Authentik, glue (Langfuse↔Dify, injection Infisical,
export Comp AI), portail d'entrée, branding, scripts bootstrap, `.env.example`, docs.

❌ **Hors périmètre** (phase ultérieure) : réécriture des outils OSS, portail admin
multi-tenant custom, provisioning automatisé de clients, billing/abonnements intégré.
