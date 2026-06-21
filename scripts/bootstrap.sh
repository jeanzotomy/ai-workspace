#!/usr/bin/env bash
# =============================================================================
# scripts/bootstrap.sh — Amorçage AI Workspace (idempotent, sûr à relancer)
# =============================================================================
# Étapes :
#   1. Vérification des prérequis (docker, docker compose, git, openssl, mc)
#   2. Génération de .env depuis .env.example si absent (secrets aléatoires forts)
#   3. Clone de vendor/comp (Comp AI — build from source, pas d'image publiée)
#   4. Création du réseau docker aiws
#   5. Création des volumes docker externes
#   6. Démarrage de MinIO seul + création des buckets dify et langfuse
#   7. Affichage des prochaines étapes
#
# Usage :
#   bash scripts/bootstrap.sh           # première installation
#   bash scripts/bootstrap.sh --force   # regénère .env même s'il existe
#
# Variables attendues dans .env.example :
#   Tous les <générer> seront remplacés par openssl rand.
#   Les <prod: gérer via Infisical> et <créer ...> sont laissés en place (à remplir manuellement).
# =============================================================================

set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}=== $* ===${NC}"; }

# ── Répertoire racine du projet ───────────────────────────────────────────────
# Bootstrap doit être lancé depuis la racine du projet
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"
info "Project root: ${PROJECT_ROOT}"

# ── Arguments ────────────────────────────────────────────────────────────────
FORCE_REGEN_ENV=false
for arg in "$@"; do
    case "$arg" in
        --force) FORCE_REGEN_ENV=true ;;
    esac
done

# =============================================================================
# ÉTAPE 1 — Vérification des prérequis
# =============================================================================
header "Étape 1/6 — Vérification des prérequis"

check_cmd() {
    local cmd="$1"
    local hint="${2:-}"
    if command -v "${cmd}" &>/dev/null; then
        success "${cmd} disponible"
    else
        error "${cmd} manquant${hint:+ — $hint}"
        exit 1
    fi
}

check_cmd docker         "Installer Docker Engine : https://docs.docker.com/engine/install/"
check_cmd git            "Installer git"
check_cmd openssl        "Installer openssl"

# docker compose (plugin v2) ou docker-compose (standalone v1)
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    success "docker compose (plugin v2) disponible"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    warn "docker-compose v1 détecté — migration vers le plugin v2 recommandée"
else
    error "docker compose introuvable. Installer le plugin Docker Compose v2."
    exit 1
fi

# mc (MinIO client) — peut être absent, on le récupère via docker si manquant
if command -v mc &>/dev/null; then
    MC_CMD="mc"
    success "mc (MinIO client) disponible"
else
    warn "mc absent — les buckets MinIO seront créés via un conteneur temporaire"
    MC_CMD=""
fi

# =============================================================================
# ÉTAPE 2 — Génération de .env
# =============================================================================
header "Étape 2/6 — Génération de .env"

ENV_FILE="${PROJECT_ROOT}/.env"
ENV_EXAMPLE="${PROJECT_ROOT}/.env.example"

if [[ ! -f "${ENV_EXAMPLE}" ]]; then
    error ".env.example introuvable dans ${PROJECT_ROOT}"
    exit 1
fi

if [[ -f "${ENV_FILE}" ]] && [[ "${FORCE_REGEN_ENV}" == "false" ]]; then
    warn ".env existe déjà — ignoré. Utiliser --force pour regénérer."
else
    info "Génération de .env depuis .env.example..."
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"

    # Fonction : remplacer les occurrences de <générer> par un secret aléatoire
    # Chaque occurrence obtient son propre secret unique
    generate_secret_32() { openssl rand -hex 32; }
    generate_secret_16() { openssl rand -hex 16; }
    generate_password()  { openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32; }

    # Remplacement ligne par ligne pour garantir l'unicité de chaque secret
    # On utilise python3 si disponible (plus robuste pour le parsing), sinon sed
    if command -v python3 &>/dev/null; then
        python3 - "${ENV_FILE}" <<'PYEOF'
import sys, re, subprocess, os

path = sys.argv[1]
with open(path, 'r') as f:
    lines = f.readlines()

result = []
for line in lines:
    if '=<générer>' in line or '=<générer> ' in line:
        varname = line.split('=')[0]
        # Détecter si on veut 16 ou 32 octets selon le commentaire
        if '16 octets' in line or 'hex 16' in line or 'SALT' in varname or 'ENCRYPTION_KEY' in varname:
            secret = subprocess.check_output(['openssl', 'rand', '-hex', '16']).decode().strip()
        else:
            secret = subprocess.check_output(['openssl', 'rand', '-hex', '32']).decode().strip()
        # Conserver le commentaire éventuel en fin de ligne
        comment_match = re.search(r'(#.*)$', line)
        comment = '  ' + comment_match.group(1) if comment_match else ''
        line = f'{varname}={secret}{comment}\n'
    result.append(line)

with open(path, 'w') as f:
    f.writelines(result)
PYEOF
    else
        # Fallback sed — remplace <générer> par un secret (moins précis pour l'unicité)
        warn "python3 absent — utilisation de sed (secrets moins différenciés)"
        while IFS= read -r line; do
            if echo "${line}" | grep -q '=<générer>'; do
                varname="$(echo "${line}" | cut -d= -f1)"
                secret="$(openssl rand -hex 32)"
                echo "${varname}=${secret}"
            else
                echo "${line}"
            fi
        done < "${ENV_FILE}" > "${ENV_FILE}.tmp"
        mv "${ENV_FILE}.tmp" "${ENV_FILE}"
    fi

    # Sécuriser le fichier (lecture propriétaire seulement)
    chmod 600 "${ENV_FILE}"
    success ".env généré avec secrets aléatoires (chmod 600)"

    warn "ACTIONS MANUELLES requises dans .env :"
    warn "  - AUTHENTIK_BOOTSTRAP_EMAIL : votre email admin"
    warn "  - ACME_EMAIL : email pour Let's Encrypt"
    warn "  - DOMAIN : votre domaine (ex: ai.monentreprise.com)"
    warn "  - Clés API LLM (OPENAI_API_KEY, etc.) — ou via Infisical en prod"
    warn "  - OPENWEBUI_OIDC_CLIENT_ID/SECRET : après avoir configuré Authentik"
    warn "  - LANGFUSE_OIDC_CLIENT_ID/SECRET : idem"
    warn "  - COMPAI_OIDC_CLIENT_ID/SECRET : idem"
fi

# Charger les variables d'env pour les étapes suivantes
# shellcheck source=/dev/null
set -a
source "${ENV_FILE}"
set +a

# =============================================================================
# ÉTAPE 3 — Clone Comp AI (build from source — pas d'image Docker publiée)
# =============================================================================
header "Étape 3/6 — Comp AI (vendor/comp)"

VENDOR_COMP="${PROJECT_ROOT}/vendor/comp"

if [[ -d "${VENDOR_COMP}/.git" ]]; then
    success "vendor/comp déjà cloné — mise à jour..."
    git -C "${VENDOR_COMP}" fetch --quiet origin
    git -C "${VENDOR_COMP}" pull --quiet --ff-only origin main 2>/dev/null || \
        warn "Impossible de mettre à jour vendor/comp (pas de réseau ou conflit). Continuation."
else
    info "Clonage de trycompai/comp dans vendor/comp..."
    git clone --depth=1 https://github.com/trycompai/comp.git "${VENDOR_COMP}"
    success "vendor/comp cloné"
fi

# =============================================================================
# ÉTAPE 4 — Réseau docker aiws
# =============================================================================
header "Étape 4/6 — Réseau docker 'aiws'"

if docker network inspect aiws &>/dev/null 2>&1; then
    success "Réseau 'aiws' existe déjà"
else
    docker network create --driver bridge aiws
    success "Réseau 'aiws' créé"
fi

# =============================================================================
# ÉTAPE 5 — Volumes docker externes
# =============================================================================
header "Étape 5/6 — Volumes docker externes"

VOLUMES=(
    postgres_data
    redis_data
    minio_data
    clickhouse_data
    qdrant_data
    authentik_media
    authentik_certs
)

for vol in "${VOLUMES[@]}"; do
    if docker volume inspect "${vol}" &>/dev/null 2>&1; then
        success "Volume '${vol}' existe déjà"
    else
        docker volume create "${vol}"
        success "Volume '${vol}' créé"
    fi
done

# =============================================================================
# ÉTAPE 6 — Démarrage MinIO + création des buckets
# =============================================================================
header "Étape 6/6 — MinIO : démarrage + buckets"

# Vérifier que les variables MinIO sont définies
if [[ -z "${MINIO_ROOT_USER:-}" ]] || [[ -z "${MINIO_ROOT_PASSWORD:-}" ]]; then
    error "MINIO_ROOT_USER ou MINIO_ROOT_PASSWORD non définis dans .env"
    exit 1
fi

# Démarrer MinIO seul
info "Démarrage du service MinIO..."
${COMPOSE_CMD} -f "${PROJECT_ROOT}/compose/infra.yml" up -d minio

# Attendre que MinIO soit healthy
info "Attente du healthcheck MinIO (max 60s)..."
MINIO_READY=false
for i in $(seq 1 12); do
    if docker inspect --format='{{.State.Health.Status}}' minio 2>/dev/null | grep -q "healthy"; then
        MINIO_READY=true
        break
    fi
    sleep 5
    info "Attente MinIO... (${i}/12)"
done

if [[ "${MINIO_READY}" == "false" ]]; then
    error "MinIO n'est pas healthy après 60s. Vérifier les logs : docker logs minio"
    exit 1
fi
success "MinIO est healthy"

# Créer les buckets via mc
MINIO_ENDPOINT="http://localhost:9000"
BUCKETS_TO_CREATE=("dify" "langfuse")

if [[ -n "${MC_CMD}" ]]; then
    # mc disponible localement
    info "Configuration de l'alias MinIO local..."
    mc alias set aiws-minio "${MINIO_ENDPOINT}" \
        "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" --quiet

    for bucket in "${BUCKETS_TO_CREATE[@]}"; do
        if mc ls "aiws-minio/${bucket}" &>/dev/null 2>&1; then
            success "Bucket '${bucket}' existe déjà"
        else
            mc mb "aiws-minio/${bucket}" --quiet
            success "Bucket '${bucket}' créé"
        fi
    done
else
    # mc via conteneur temporaire
    info "Création des buckets via conteneur mc temporaire..."
    docker run --rm \
        --network aiws \
        --entrypoint /bin/sh \
        minio/mc:latest -c "
            mc alias set aiws-minio http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' --quiet
            mc mb --ignore-existing aiws-minio/dify
            mc mb --ignore-existing aiws-minio/langfuse
            echo 'Buckets dify et langfuse créés/vérifiés.'
        "
    success "Buckets dify et langfuse prêts"
fi

# Optionnel : bucket comp-ai pour les pièces justificatives
COMPAI_BUCKET="${COMPAI_STORAGE_BUCKET:-comp-ai-evidence}"
if [[ -n "${MC_CMD}" ]]; then
    if ! mc ls "aiws-minio/${COMPAI_BUCKET}" &>/dev/null 2>&1; then
        mc mb "aiws-minio/${COMPAI_BUCKET}" --quiet
        success "Bucket '${COMPAI_BUCKET}' créé"
    else
        success "Bucket '${COMPAI_BUCKET}' existe déjà"
    fi
else
    docker run --rm \
        --network aiws \
        --entrypoint /bin/sh \
        minio/mc:latest -c "
            mc alias set aiws-minio http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' --quiet
            mc mb --ignore-existing aiws-minio/${COMPAI_BUCKET}
        "
fi

# =============================================================================
# RÉSUMÉ ET PROCHAINES ÉTAPES
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}=====================================================${NC}"
echo -e "${BOLD}${GREEN}  AI Workspace Bootstrap terminé avec succès !       ${NC}"
echo -e "${BOLD}${GREEN}=====================================================${NC}"
echo ""
echo -e "${BOLD}Prochaines étapes :${NC}"
echo ""
echo -e "  ${CYAN}1. Vérifier/compléter .env${NC}"
echo -e "     nano .env"
echo -e "     Définir : DOMAIN, ACME_EMAIL, AUTHENTIK_BOOTSTRAP_EMAIL"
echo ""
echo -e "  ${CYAN}2. Démarrer la stack complète${NC}"
echo -e "     make up"
echo -e "     # ou : ${COMPOSE_CMD} up -d"
echo ""
echo -e "  ${CYAN}3. DNS (prod) — Configurer un wildcard DNS${NC}"
echo -e "     *.${DOMAIN:-ai.example.com}  →  IP de votre VM"
echo ""
echo -e "  ${CYAN}4. DNS (dev local) — Ajouter à /etc/hosts ou dnsmasq${NC}"
echo -e "     127.0.0.1  auth.aiws.localhost"
echo -e "     127.0.0.1  chat.aiws.localhost"
echo -e "     127.0.0.1  dify.aiws.localhost"
echo -e "     127.0.0.1  observe.aiws.localhost"
echo -e "     127.0.0.1  secrets.aiws.localhost"
echo -e "     127.0.0.1  compliance.aiws.localhost"
echo -e "     127.0.0.1  traefik.aiws.localhost"
echo -e "     127.0.0.1  aiws.localhost"
echo ""
echo -e "  ${CYAN}5. Accéder à Authentik et configurer les providers OIDC${NC}"
echo -e "     https://auth.${DOMAIN:-aiws.localhost}"
echo -e "     Appliquer le blueprint : config/authentik/blueprints/ai-workspace.yaml"
echo -e "     Reporter les client_id/secret dans .env"
echo ""
echo -e "  ${CYAN}6. Santé de la stack${NC}"
echo -e "     make health"
echo -e "     # ou : bash scripts/healthcheck.sh"
echo ""
echo -e "  ${CYAN}7. Lire INTEGRATION.md pour connecter Dify → Langfuse${NC}"
echo -e "     cat docs/INTEGRATION.md"
echo ""
echo -e "${YELLOW}RAPPEL SÉCURITÉ :${NC}"
echo -e "  - .env est confidentiel (chmod 600, hors git)"
echo -e "  - Changer AUTHENTIK_BOOTSTRAP_PASSWORD après le premier login"
echo -e "  - En prod, gérer les clés API LLM via Infisical"
echo ""
