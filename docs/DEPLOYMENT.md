# AI Workspace — Guide de déploiement

> Self-hosted sur VM (recommandé) ou local (dev).
> Stack lourde avec état (PostgreSQL, Redis, MinIO, ClickHouse, Qdrant) — pas serverless.

---

## Table des matières

1. [Déploiement local (dev)](#1-déploiement-local-dev)
2. [Déploiement VM self-host (prod)](#2-déploiement-vm-self-host-prod)
3. [Sauvegardes](#3-sauvegardes)
4. [Mise à jour](#4-mise-à-jour)
5. [Monitoring et sécurité](#5-monitoring-et-sécurité)
6. [Estimation des ressources et coûts](#6-estimation-des-ressources-et-coûts)

---

## 1. Déploiement local (dev)

### Prérequis

| Outil | Version min | Notes |
|---|---|---|
| Docker Engine | 24.x | [docker.com/engine/install](https://docs.docker.com/engine/install/) |
| Docker Compose | v2.x | Inclus avec Docker Desktop |
| Git | 2.x | Pour cloner et vendor/comp |
| openssl | — | Génération de secrets |
| RAM disponible | 8 Go min | 16 Go recommandé avec Dify + Langfuse + Authentik |
| Disque libre | 20 Go | Images + données |

### Résolution DNS locale

Deux approches (choisir une) :

**Option A — /etc/hosts (simple, manuel)**

Ajouter à `/etc/hosts` (Linux/macOS) ou `C:\Windows\System32\drivers\etc\hosts` (Windows) :
```
127.0.0.1  aiws.localhost
127.0.0.1  auth.aiws.localhost
127.0.0.1  chat.aiws.localhost
127.0.0.1  dify.aiws.localhost
127.0.0.1  observe.aiws.localhost
127.0.0.1  secrets.aiws.localhost
127.0.0.1  compliance.aiws.localhost
127.0.0.1  traefik.aiws.localhost
```

**Option B — dnsmasq (wildcard, recommandé pour dev)**

```bash
# macOS
brew install dnsmasq
echo "address=/.aiws.localhost/127.0.0.1" >> /usr/local/etc/dnsmasq.conf
sudo brew services start dnsmasq
# Configurer 127.0.0.1 comme DNS dans System Preferences

# Linux (NetworkManager)
echo "address=/.aiws.localhost/127.0.0.1" | sudo tee /etc/NetworkManager/dnsmasq.d/aiws.conf
sudo systemctl reload NetworkManager
```

### Certificats TLS locaux (mkcert)

```bash
# Installer mkcert
brew install mkcert  # macOS
# ou : https://github.com/FiloSottile/mkcert#installation

mkcert -install  # Installe la CA locale dans le store système

# Générer le certificat wildcard
mkcert "*.aiws.localhost" aiws.localhost
# Génère : _wildcard.aiws.localhost+1.pem et _wildcard.aiws.localhost+1-key.pem

# Copier dans le dossier Traefik (chemin à adapter selon compose/traefik.yml)
mkdir -p certs/
cp _wildcard.aiws.localhost+1.pem     certs/local.pem
cp _wildcard.aiws.localhost+1-key.pem certs/local-key.pem
```

Dans `.env`, définir `DOMAIN=aiws.localhost` et désactiver ACME :
```env
DOMAIN=aiws.localhost
ACME_EMAIL=dev@localhost
```

Le compose Traefik détecte automatiquement les certificats locaux si le dossier `certs/`
est monté dans le conteneur Traefik (voir `compose/traefik.yml`).

### Démarrage en local

```bash
# 1. Cloner le dépôt
git clone <repo-url> ai-workspace
cd ai-workspace

# 2. Bootstrap (génère .env, crée réseau + volumes, démarre MinIO, crée buckets)
make bootstrap
# ou : bash scripts/bootstrap.sh

# 3. Vérifier .env (définir DOMAIN=aiws.localhost au minimum)
nano .env

# 4. Démarrer la stack complète
make up
# ou : docker compose up -d

# 5. Suivre les logs (les premiers démarrages prennent 2-5 min)
make logs
# ou : docker compose logs -f --tail=50

# 6. Vérifier la santé
make health
# ou : bash scripts/healthcheck.sh
```

**Ordre de démarrage recommandé pour le debug :**
```bash
# Infrastructure d'abord
docker compose -f compose/infra.yml up -d

# Attendre que postgres soit healthy
docker compose ps postgres  # vérifier "healthy"

# Proxy + IdP
docker compose -f compose/traefik.yml up -d
docker compose -f compose/authentik.yml up -d

# Applications
docker compose up -d
```

### Accès en local

| Service | URL | Identifiants par défaut |
|---|---|---|
| Portail | https://aiws.localhost | public |
| Authentik | https://auth.aiws.localhost | admin / voir AUTHENTIK_BOOTSTRAP_PASSWORD dans .env |
| Open WebUI | https://chat.aiws.localhost | créer un compte (1er = admin) |
| Dify | https://dify.aiws.localhost | créer un compte admin |
| Langfuse | https://observe.aiws.localhost | créer un compte |
| Infisical | https://secrets.aiws.localhost | créer un compte |
| Comp AI | https://compliance.aiws.localhost | créer un compte |
| Traefik | https://traefik.aiws.localhost/dashboard/ | auth Authentik |

---

## 2. Déploiement VM self-host (prod)

### Spécifications VM recommandées

| Composant | Minimum (5-10 users) | Recommandé (20-50 users) | GPU (modèles locaux) |
|---|---|---|---|
| vCPU | 4 | 8 | 8 + |
| RAM | 16 Go | 32 Go | 32 Go + |
| SSD NVMe | 100 Go | 250 Go | 500 Go + |
| Réseau | 100 Mbps | 1 Gbps | 1 Gbps |
| GPU | — | — | NVIDIA RTX 4090 / A100 |

**OS recommandé** : Ubuntu 24.04 LTS ou Debian 12 (Bookworm).
Rocky Linux 9 / RHEL 9 sont aussi supportés.

**Providers cloud compatibles** (VM standard) :
- OVH VPS / Baremetal (coût optimal Europe/Afrique)
- Hetzner CPX31/CPX51 (excellent rapport qualité/prix EU)
- DigitalOcean Droplet
- Scaleway DEV1-M / GP1-S
- Azure VM B4ms / D4s v3
- AWS EC2 t3.xlarge / c5.xlarge

### Installation Docker sur Ubuntu 24.04

```bash
# Mise à jour système
sudo apt update && sudo apt upgrade -y

# Installer Docker Engine (méthode officielle apt)
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Ajouter l'utilisateur courant au groupe docker
sudo usermod -aG docker $USER
newgrp docker

# Vérifier
docker --version
docker compose version
```

### DNS wildcard (obligatoire en prod)

Chez votre registrar DNS, créer un enregistrement wildcard :

```
*.ai.monentreprise.com.   IN A   <IP_publique_VM>
ai.monentreprise.com.     IN A   <IP_publique_VM>
```

Attendre la propagation DNS (5-30 min) avant de démarrer la stack.

Vérifier la propagation :
```bash
dig +short chat.ai.monentreprise.com
# Doit retourner l'IP de votre VM
```

### Ports à ouvrir (firewall)

```bash
# UFW (Ubuntu)
sudo ufw allow 22/tcp    # SSH (restreindre à votre IP si possible)
sudo ufw allow 80/tcp    # HTTP → redirect HTTPS
sudo ufw allow 443/tcp   # HTTPS (Traefik + ACME)
sudo ufw enable

# Bloquer l'accès direct aux ports internes
# (9000 MinIO, 5432 Postgres, 6379 Redis ne doivent pas être exposés)
sudo ufw deny 9000/tcp
sudo ufw deny 5432/tcp
sudo ufw deny 6379/tcp
```

### Déploiement initial

```bash
# 1. Cloner le dépôt sur la VM
git clone <repo-url> /opt/ai-workspace
cd /opt/ai-workspace

# 2. Bootstrap
bash scripts/bootstrap.sh

# 3. Configurer .env pour la prod
nano .env
# OBLIGATOIRE à définir :
#   DOMAIN=ai.monentreprise.com
#   ACME_EMAIL=admin@monentreprise.com
#   AUTHENTIK_BOOTSTRAP_EMAIL=admin@monentreprise.com
#   TZ=Africa/Abidjan  (ou votre timezone)

# 4. Démarrer la stack
docker compose up -d

# 5. Surveiller le démarrage (5-10 min premier démarrage)
docker compose logs -f --tail=50

# 6. Vérifier la santé
bash scripts/healthcheck.sh
```

### Certificats ACME (Let's Encrypt automatique)

Traefik gère les certificats Let's Encrypt automatiquement via le challenge HTTP-01.
**Aucune action manuelle requise** si les DNS pointent vers votre IP et les ports 80/443 sont ouverts.

Les certificats sont stockés dans le volume `traefik_acme` et renouvelés automatiquement
avant expiration (Traefik le gère en arrière-plan).

**Vérifier que le certificat est valide** :
```bash
curl -vI https://chat.ai.monentreprise.com 2>&1 | grep "SSL certificate"
# Doit afficher le certificat Let's Encrypt avec la bonne expiration
```

**Rate limits Let's Encrypt** : max 5 certificats par domaine par semaine en prod.
Pour les tests, utiliser le serveur staging en ajoutant dans `compose/traefik.yml` :
```yaml
--certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
```

---

## 3. Sauvegardes

La stack a **deux types de données à sauvegarder** :

### 3.1 PostgreSQL (source de vérité applicative)

```bash
#!/usr/bin/env bash
# scripts/backup-postgres.sh — à planifier via cron
set -euo pipefail

source /opt/ai-workspace/.env

BACKUP_DIR="/backup/postgres/$(date +%Y-%m-%d)"
mkdir -p "${BACKUP_DIR}"

# Dump de chaque base séparément (facilite la restauration sélective)
for DB in authentik dify langfuse infisical compai; do
    echo "Dump ${DB}..."
    docker exec postgres pg_dump \
        -U "${POSTGRES_USER}" \
        --no-password \
        --format=custom \
        --compress=9 \
        "${DB}" > "${BACKUP_DIR}/${DB}.dump"
done

# Nettoyage : garder 7 jours
find /backup/postgres -maxdepth 1 -type d -mtime +7 -exec rm -rf {} +

echo "Backup terminé : ${BACKUP_DIR}"
```

Ajouter au crontab (`crontab -e`) :
```cron
0 2 * * * /opt/ai-workspace/scripts/backup-postgres.sh >> /var/log/ai-workspace-backup.log 2>&1
```

### 3.2 MinIO (fichiers, uploads, traces)

```bash
#!/usr/bin/env bash
# Sync MinIO vers un répertoire local ou S3 externe
source /opt/ai-workspace/.env

# Option A : rsync local
docker run --rm \
    --network aiws \
    -v /backup/minio:/backup \
    minio/mc:latest sh -c "
        mc alias set aiws-minio http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}'
        mc mirror aiws-minio/dify    /backup/dify/
        mc mirror aiws-minio/langfuse /backup/langfuse/
    "

# Option B : sync vers S3 externe (OVH Object Storage, Scaleway, etc.)
# mc mirror aiws-minio/dify s3-backup/ai-workspace/dify/
```

### 3.3 Restauration

```bash
# Restaurer une base PostgreSQL
docker exec -i postgres pg_restore \
    -U postgres \
    --no-password \
    -d dify \
    --clean \
    --if-exists \
    < /backup/postgres/2026-06-21/dify.dump

# Restaurer MinIO
docker run --rm \
    --network aiws \
    -v /backup/minio:/backup \
    minio/mc:latest sh -c "
        mc alias set aiws-minio http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}'
        mc mirror /backup/dify/ aiws-minio/dify/
    "
```

---

## 4. Mise à jour

### Mise à jour des images OSS

```bash
cd /opt/ai-workspace

# 1. Sauvegarder avant la mise à jour
bash scripts/backup-postgres.sh

# 2. Mettre à jour les versions dans les fichiers compose et .env
# Vérifier les releases officielles :
#   - Dify : https://github.com/langgenius/dify/releases
#   - Langfuse : https://github.com/langfuse/langfuse/releases
#   - Authentik : https://goauthentik.io/docs/releases
# Mettre à jour DIFY_VERSION, LANGFUSE_VERSION dans .env

# 3. Tirer les nouvelles images
docker compose pull

# 4. Redémarrer (les migrations DB se font automatiquement au boot pour Dify/Langfuse)
docker compose up -d --remove-orphans

# 5. Vérifier
bash scripts/healthcheck.sh
docker compose logs --tail=100 dify-api langfuse-web
```

### Mise à jour du code du dépôt (configurations)

```bash
cd /opt/ai-workspace
git pull origin main
docker compose up -d --remove-orphans
```

---

## 5. Monitoring et sécurité

### Logs centralisés

```bash
# Voir les logs de tous les services
docker compose logs -f --tail=100

# Service spécifique
docker compose logs -f dify-api
docker compose logs -f langfuse-web

# Logs persistants sur disque
# Configurer dans docker-compose.yml :
# logging:
#   driver: "json-file"
#   options:
#     max-size: "10m"
#     max-file: "3"
```

### Monitoring des ressources

```bash
# Vue temps réel
docker stats

# Détail par service
docker stats postgres redis minio clickhouse qdrant

# Espace disque utilisé par les volumes
docker system df
docker volume ls
```

### Fail2ban (protection SSH + Traefik)

```bash
sudo apt install -y fail2ban

# /etc/fail2ban/jail.local
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true

[traefik-auth]
enabled  = true
port     = http,https
filter   = traefik-auth
logpath  = /var/log/traefik/access.log
maxretry = 10
bantime  = 1h
EOF

sudo systemctl restart fail2ban
```

### Rotation des secrets

Planification recommandée :
- **Tous les 90 jours** : `AUTHENTIK_SECRET_KEY`, `DIFY_SECRET_KEY`, `LANGFUSE_NEXTAUTH_SECRET`, `OPENWEBUI_SECRET_KEY`
- **Tous les 6 mois** : `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `MINIO_ROOT_PASSWORD`
- **Après chaque départ d'admin** : tous les secrets immédiatement

Procédure de rotation d'un secret :
```bash
# 1. Générer le nouveau secret
NEW_SECRET=$(openssl rand -hex 32)

# 2. Mettre à jour .env
sed -i "s/^AUTHENTIK_SECRET_KEY=.*/AUTHENTIK_SECRET_KEY=${NEW_SECRET}/" .env

# 3. Redémarrer le(s) service(s) concerné(s)
docker compose restart authentik-server authentik-worker

# 4. Vérifier
bash scripts/healthcheck.sh
```

---

## 6. Estimation des ressources et coûts

### Utilisation mémoire typique (stack complète)

| Service | RAM au repos | RAM sous charge |
|---|---|---|
| postgres | 128 Mo | 512 Mo |
| redis | 64 Mo | 256 Mo |
| minio | 256 Mo | 512 Mo |
| clickhouse | 256 Mo | 1 Go |
| qdrant | 256 Mo | 1 Go |
| traefik | 32 Mo | 64 Mo |
| authentik-server | 256 Mo | 512 Mo |
| authentik-worker | 128 Mo | 256 Mo |
| open-webui | 256 Mo | 512 Mo |
| dify-api | 512 Mo | 1 Go |
| dify-worker | 256 Mo | 512 Mo |
| dify-web | 128 Mo | 256 Mo |
| dify-nginx | 32 Mo | 64 Mo |
| dify-sandbox | 128 Mo | 256 Mo |
| langfuse-web | 256 Mo | 512 Mo |
| langfuse-worker | 256 Mo | 512 Mo |
| infisical | 256 Mo | 512 Mo |
| comp-ai | 256 Mo | 512 Mo |
| **TOTAL** | **~3.5 Go** | **~8 Go** |

Recommandation : **16 Go RAM minimum** pour absorber les pics et les migrations au démarrage.

### Estimation coûts hébergement VM (€/mois, 2026)

| Provider | Spec | Prix/mois | Notes |
|---|---|---|---|
| Hetzner CPX31 | 4 vCPU / 8 Go | ~15 € | Minimum absolu — 8 Go RAM peut suffire en prod légère |
| Hetzner CPX41 | 8 vCPU / 16 Go | ~29 € | **Recommandé pour 5-20 users** |
| Hetzner CPX51 | 16 vCPU / 32 Go | ~59 € | Confortable pour 20-50 users |
| OVH VPS Value | 4 vCPU / 8 Go | ~20 € | Datacenter EU/Afrique |
| Scaleway DEV1-M | 3 vCPU / 4 Go | ~10 € | Test uniquement (RAM insuffisante) |
| Azure B4ms | 4 vCPU / 16 Go | ~120 € | Si déjà sur Azure |
| AWS t3.xlarge | 4 vCPU / 16 Go | ~130 € | Si déjà sur AWS |

### Coûts tokens LLM (variables — non inclus VM)

Dépend du volume de prompts. Exemple pour 1M tokens/mois (Plan Starter) :

| Provider | Coût estimé |
|---|---|
| GPT-4o mini | ~0.15 $/1M tokens input = ~0.15 $ |
| GPT-4o | ~2.50 $/1M tokens input = ~2.50 $ |
| Claude 3.5 Sonnet | ~3.00 $/1M tokens input = ~3.00 $ |
| Mistral Large | ~2.00 $/1M tokens input = ~2.00 $ |
| Ollama (local GPU) | 0 $ (coût électricité) |

### Total opérationnel estimé

| Scénario | VM | Tokens | Total/mois |
|---|---|---|---|
| Dev/demo | Hetzner CPX31 (15 €) | Gratuit (API dev) | ~15 € |
| Starter (5 users) | Hetzner CPX41 (29 €) | 1M tok ~5 € | ~35 € |
| Business (25 users) | Hetzner CPX51 (59 €) | 10M tok ~50 € | ~110 € |
| Enterprise (100 users) | 2× CPX51 + backup (130 €) | 100M tok ~500 € | ~630 € |

Ces chiffres confirment la fourchette annoncée dans FEATURES.md : **400–900 €/mois opérationnel**.
La marge provient de la différence entre coût infra (35–630 €) et prix de vente (499–4 999 €/mois).
