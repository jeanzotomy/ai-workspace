# AI Workspace d'Entreprise

**Suite IA self-hosted RGPD-native** — alternative à Azure OpenAI Studio + Datadog LLM.
Données 100 % locales, coût ~10× moins cher, un seul `docker-compose`.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![docker-compose](https://img.shields.io/badge/docker--compose-v2-2496ED?logo=docker)](docker-compose.yml)
[![self-hosted](https://img.shields.io/badge/deployment-self--hosted-green)](docs/DEPLOYMENT.md)

---

## Pitch

Les organisations qui adoptent des LLM en entreprise se heurtent à trois obstacles :
coût élevé des services cloud managés, souveraineté des données insuffisante, et
fragmentation des outils (chat, orchestration, observabilité, conformité en silos séparés).

AI Workspace réunit cinq briques OSS éprouvées (Dify, Open WebUI, Langfuse, Infisical,
Comp AI) derrière un reverse proxy unique (Traefik) et un IdP SSO (Authentik), orchestrés
par un seul `docker-compose`. Résultat : une infrastructure IA d'entreprise opérationnelle
en moins d'une journée, hébergée sur votre propre VM, sans donnée qui sort de votre réseau.

---

## Architecture

```
                        Internet (HTTPS 443)
                                │
                        ┌───────▼────────┐
                        │    Traefik     │  reverse proxy + TLS ACME
                        │  (edge router) │  + forwardAuth → Authentik
                        └───────┬────────┘
      ┌──────────┬──────────┬───┴────┬───────────┬────────────┐
      │          │          │        │           │            │
 ${DOMAIN}   chat.    dify.   observe.  secrets.  compliance.  auth.
 (portal)  OpenWebUI  Dify    Langfuse  Infisical   Comp AI   Authentik
      │          │          │        │           │            │
      └──────────┴──────────┴────────┴───────────┴────────────┘
                        réseau docker : aiws (bridge)
      ┌─────────────── infra partagée (réseau aiws) ──────────────────┐
      │  postgres (multi-bases)  ·  redis  ·  minio (S3)              │
      │  clickhouse (Langfuse)   ·  qdrant (Dify vector store)        │
      └───────────────────────────────────────────────────────────────┘
```

---

## Composants

| Brique | Rôle | Sous-domaine | Type |
|---|---|---|---|
| **Dify** | Orchestration IA : pipelines RAG, agents, workflows visuels, API OpenAI-compatible | `dify.${DOMAIN}` | Core |
| **Open WebUI** | Interface de chat multi-modèles (local + cloud) | `chat.${DOMAIN}` | Core |
| **Langfuse** | Observabilité LLM : traces, coûts tokens, évaluations qualité | `observe.${DOMAIN}` | Core |
| **Infisical** | Gestion des secrets LLM (clés API, rotation, audit) | `secrets.${DOMAIN}` | Support |
| **Comp AI** | Conformité : SOC 2, ISO 27001, RGPD, audit trails | `compliance.${DOMAIN}` | Optionnel |
| **Authentik** | Fournisseur OIDC SSO pour toute la suite | `auth.${DOMAIN}` | Intégration |
| **Traefik** | Reverse proxy, TLS automatique (Let's Encrypt), forwardAuth | — | Intégration |
| **AI Workspace Portal** | Page d'accueil unifiée, statut santé, branding | `${DOMAIN}` | Intégration |
| **Postgres** | SGBD multi-bases (Dify, Langfuse, Infisical, Comp AI, Authentik) | — | Infra |
| **Redis** | Cache et files de messages | — | Infra |
| **MinIO** | Stockage objet S3 (uploads Dify, events Langfuse) | — | Infra |
| **ClickHouse** | Analytics traces (Langfuse v3) | — | Infra |
| **Qdrant** | Vector store (RAG Dify) | — | Infra |

---

## Démarrage rapide

### Prérequis

- Docker Engine >= 24 et Docker Compose v2
- VM recommandée : 4 vCPU, 16 Go RAM, 100 Go SSD (voir [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md))
- DNS : entrée wildcard `*.${DOMAIN}` pointant vers l'IP de votre VM
- Ports ouverts : 80, 443

### Lancement

```bash
git clone https://github.com/jeanzotomy/ai-workspace.git
cd ai-workspace

make bootstrap     # génère .env + secrets, buckets MinIO, bases Postgres

# Éditer .env :
#   DOMAIN=ai.example.com
#   ACME_EMAIL=admin@example.com
#   Clés API LLM (OpenAI, Anthropic, Mistral…)

make up            # démarre toute la suite (premier lancement ~5 min)
make health        # vérifie l'état de tous les services
```

### Accès après démarrage

| URL | Service |
|---|---|
| `https://${DOMAIN}` | Portail d'entrée unifié |
| `https://chat.${DOMAIN}` | Open WebUI (chat LLM) |
| `https://dify.${DOMAIN}` | Dify (pipelines IA) |
| `https://observe.${DOMAIN}` | Langfuse (observabilité) |
| `https://secrets.${DOMAIN}` | Infisical (secrets) |
| `https://compliance.${DOMAIN}` | Comp AI (conformité) |
| `https://auth.${DOMAIN}` | Authentik (SSO admin) |

> Le DNS wildcard `*.${DOMAIN}` est requis. Sans lui, chaque sous-domaine devra être
> déclaré manuellement dans votre zone DNS.

---

## Différenciateurs clés

**Intégration Langfuse + Dify via OpenTelemetry** — chaque prompt, token et coût est
tracé automatiquement sans instrumentation manuelle. Pas d'équivalent dans les offres
cloud managées à ce prix.

**Infisical comme gestionnaire de secrets** — les clés API LLM (OpenAI, Anthropic,
Mistral) ne sont jamais stockées en dur ni dans `.env` en production. Elles sont
injectées dynamiquement par Infisical Agent, avec audit log complet de chaque accès.

**RGPD-native par construction** — les données ne quittent jamais votre infrastructure.
Langfuse et Comp AI alimentent un registre de traitements IA conforme à l'article 30
du RGPD.

---

## Matrice SSO

Authentik est le fournisseur OIDC central. Le niveau de support varie selon les briques.

| Brique | OIDC natif | Stratégie actuelle |
|---|---|---|
| Open WebUI | Oui | `OAUTH_*` / `OPENID_PROVIDER_URL` → Authentik |
| Langfuse | Oui | `AUTH_CUSTOM_*` (OIDC custom) → Authentik |
| Comp AI | Oui (OAuth) | Provider OAuth → Authentik |
| Dify | Partiel (OIDC = édition entreprise) | Login natif + Traefik forwardAuth devant la console |
| Infisical | Partiel (OIDC/SAML = tier payant) | Login natif + Traefik forwardAuth devant l'UI |

Le forwardAuth Traefik protège le périmètre réseau pour Dify et Infisical. Le SSO
applicatif complet sur ces deux briques nécessite leurs éditions entreprise respectives.

Voir [docs/ARCHITECTURE.md §6](docs/ARCHITECTURE.md) pour le détail de la configuration.

---

## Documentation

| Document | Contenu |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Topologie, réseau, sous-domaines, conventions, matrice SSO — source de vérité technique |
| [docs/FEATURES.md](docs/FEATURES.md) | Inventaire fonctionnel complet par brique |
| [docs/INTEGRATION.md](docs/INTEGRATION.md) | Glue détaillée : OTel Langfuse↔Dify, injection Infisical, blueprints Authentik |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Guide déploiement VM self-host et environnement local |
| [docs/COMMERCIAL.md](docs/COMMERCIAL.md) | Offre commerciale, pricing, go-to-market, économie unitaire |

---

## Structure du dépôt

```
ai-workspace/
├── docker-compose.yml       # racine : include + réseau aiws + infra partagée
├── .env.example             # toutes les variables documentées (jamais de secrets réels)
├── compose/
│   ├── infra.yml            # postgres, redis, minio, clickhouse, qdrant
│   ├── traefik.yml          # reverse proxy + ACME + middlewares
│   ├── authentik.yml        # IdP (server + worker)
│   ├── dify.yml             # api, worker, web, nginx, sandbox, ssrf-proxy
│   ├── open-webui.yml
│   ├── langfuse.yml         # web + worker
│   ├── infisical.yml
│   └── comp-ai.yml
├── proxy/
│   └── dynamic/             # config dynamique Traefik (middlewares, forwardAuth)
├── config/
│   └── authentik/           # blueprints Authentik (providers/apps OIDC)
├── scripts/
│   ├── bootstrap.sh         # génère secrets, .env, bases Postgres
│   ├── init-multi-db.sh     # crée les bases Postgres au premier démarrage
│   └── healthcheck.sh       # statut agrégé des services
├── portal/                  # page d'accueil unifiée (HTML/CSS statique, nginx:alpine)
├── docs/
│   ├── FEATURES.md
│   ├── ARCHITECTURE.md
│   ├── INTEGRATION.md
│   ├── DEPLOYMENT.md
│   └── COMMERCIAL.md
├── Makefile                 # cibles : up, down, logs, bootstrap, health
├── README.md
├── LICENSE
└── .gitignore               # .env, volumes locaux, secrets générés
```

---

## Licence

Le code d'intégration de ce dépôt (compose, scripts, portail, docs) est publié sous
licence **MIT** — voir [LICENSE](LICENSE).

Chaque brique OSS intégrée conserve sa propre licence :

| Brique | Licence |
|---|---|
| Dify | Apache 2.0 |
| Open WebUI | MIT |
| Langfuse | MIT (self-host) |
| Infisical | MIT (self-host core) |
| Comp AI | Voir dépôt `trycompai/comp` |
| Authentik | MIT |
| Traefik | MIT |

---

## Avertissements

**Licences OSS.** Certaines fonctionnalités avancées des briques intégrées sont réservées
à leurs éditions commerciales : SSO OIDC/SAML natif sur Dify et Infisical, support
entreprise Langfuse, etc. Vérifier les conditions de licence de chaque brique avant tout
déploiement en production.

**Conformité et données.** AI Workspace fournit des outils facilitant la conformité RGPD
(Comp AI, Infisical, Langfuse). La responsabilité de la conformité effective — qualification
des traitements, DPIA, registre Art. 30, contrats sous-traitants — incombe à l'exploitant.

**Projections commerciales.** Les chiffres figurant dans [docs/COMMERCIAL.md](docs/COMMERCIAL.md)
sont des estimations indicatives basées sur des hypothèses de marché. Ils ne constituent
pas des garanties de revenus.
