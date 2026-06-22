#!/usr/bin/env bash
# =============================================================================
# scripts/healthcheck.sh — Statut agrégé de l'AI Workspace
# =============================================================================
# Interroge chaque service via docker inspect (healthcheck) et HTTP.
# Affiche un tableau coloré OK / WARN / KO par brique.
#
# Usage :
#   bash scripts/healthcheck.sh             # vérification complète
#   bash scripts/healthcheck.sh --quiet     # JSON seulement (CI/CD)
#   bash scripts/healthcheck.sh --http-only # HTTP checks sans docker inspect
# =============================================================================

set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

QUIET=false
HTTP_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --quiet)     QUIET=true ;;
        --http-only) HTTP_ONLY=true ;;
    esac
done

# Charger .env si présent (pour DOMAIN et autres variables)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

# Extraction ciblée et sûre (le .env contient des placeholders <...> et des
# commentaires avec parenthèses/apostrophes qui cassent un `source` bash ;
# Docker Compose parse le .env nativement, pas via bash).
env_get() {
    local key="$1"
    [[ -f "${ENV_FILE}" ]] || return 0
    grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"'"'"'\r' || true
}

DOMAIN="${DOMAIN:-$(env_get DOMAIN)}"
DOMAIN="${DOMAIN:-aiws.localhost}"
PROTOCOL="${HEALTHCHECK_PROTOCOL:-$(env_get HEALTHCHECK_PROTOCOL)}"
PROTOCOL="${PROTOCOL:-https}"

# ── Compteurs ─────────────────────────────────────────────────────────────────
COUNT_OK=0
COUNT_WARN=0
COUNT_KO=0

# Tableau des résultats pour le rapport JSON
declare -a RESULTS=()

# ── Helpers ──────────────────────────────────────────────────────────────────
pad_right() {
    local str="$1"
    local width="$2"
    printf "%-${width}s" "${str}"
}

status_label() {
    local status="$1"
    case "${status}" in
        OK)   echo -e "${GREEN}[  OK  ]${NC}" ;;
        WARN) echo -e "${YELLOW}[ WARN ]${NC}" ;;
        KO)   echo -e "${RED}[  KO  ]${NC}" ;;
    esac
}

# Vérification via docker inspect healthcheck
check_container() {
    local name="$1"
    local display_name="$2"
    local extra_info="${3:-}"

    local status="KO"
    local detail=""

    if ! docker inspect "${name}" &>/dev/null 2>&1; then
        detail="Conteneur absent"
    else
        local running
        running="$(docker inspect --format='{{.State.Running}}' "${name}" 2>/dev/null || echo "false")"
        local health
        health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${name}" 2>/dev/null || echo "unknown")"

        if [[ "${running}" != "true" ]]; then
            detail="Conteneur arrêté"
        elif [[ "${health}" == "healthy" ]]; then
            status="OK"
            detail="${extra_info:-healthcheck healthy}"
        elif [[ "${health}" == "none" ]]; then
            # Pas de healthcheck configuré — considérer running comme OK
            status="WARN"
            detail="Running (pas de healthcheck configuré)"
        elif [[ "${health}" == "starting" ]]; then
            status="WARN"
            detail="En démarrage (healthcheck starting)"
        else
            detail="Healthcheck: ${health}"
        fi
    fi

    RESULTS+=("{\"name\":\"${display_name}\",\"status\":\"${status}\",\"detail\":\"${detail}\"}")

    if [[ "${QUIET}" == "false" ]]; then
        printf "  %s  %s  %s\n" \
            "$(status_label "${status}")" \
            "$(pad_right "${display_name}" 22)" \
            "${detail}"
    fi

    case "${status}" in
        OK)   COUNT_OK=$((COUNT_OK+1)) ;;
        WARN) COUNT_WARN=$((COUNT_WARN+1)) ;;
        KO)   COUNT_KO=$((COUNT_KO+1)) ;;
    esac
}

# Vérification HTTP GET (avec timeout)
check_http() {
    local name="$1"
    local url="$2"
    local expected_code="${3:-200}"
    local extra_info="${4:-}"

    local status="KO"
    local detail=""
    local http_code

    http_code="$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000")"

    if [[ "${http_code}" == "${expected_code}" ]]; then
        status="OK"
        detail="${extra_info:-HTTP ${http_code}}"
    elif [[ "${http_code}" == "200" ]] || [[ "${http_code}" == "301" ]] || \
         [[ "${http_code}" == "302" ]] || [[ "${http_code}" == "307" ]] || \
         [[ "${http_code}" == "308" ]]; then
        status="OK"
        detail="HTTP ${http_code} (redirect acceptable)"
    elif [[ "${http_code}" == "000" ]]; then
        detail="Connexion refusée / timeout"
    elif [[ "${http_code}" == "401" ]] || [[ "${http_code}" == "403" ]]; then
        # 401/403 = service up mais protégé (attendu pour les services avec auth)
        status="OK"
        detail="HTTP ${http_code} (auth requise — service actif)"
    else
        detail="HTTP ${http_code} inattendu"
    fi

    RESULTS+=("{\"name\":\"${name} (HTTP)\",\"status\":\"${status}\",\"detail\":\"${detail}\"}")

    if [[ "${QUIET}" == "false" ]]; then
        printf "  %s  %s  %s\n" \
            "$(status_label "${status}")" \
            "$(pad_right "${name} (HTTP)" 22)" \
            "${detail}"
    fi

    case "${status}" in
        OK)   COUNT_OK=$((COUNT_OK+1)) ;;
        WARN) COUNT_WARN=$((COUNT_WARN+1)) ;;
        KO)   COUNT_KO=$((COUNT_KO+1)) ;;
    esac
}

# =============================================================================
# AFFICHAGE
# =============================================================================

if [[ "${QUIET}" == "false" ]]; then
    echo ""
    echo -e "${BOLD}${CYAN}AI Workspace — Health Report${NC}"
    echo -e "${CYAN}Domain: ${DOMAIN}${NC}"
    echo -e "${CYAN}Date:   $(date '+%Y-%m-%d %H:%M:%S %Z')${NC}"
    echo ""
    echo "────────────────────────────────────────────────────────────────"
    echo -e "${BOLD}Infrastructure (conteneurs)${NC}"
    echo "────────────────────────────────────────────────────────────────"
fi

# ── Infra ────────────────────────────────────────────────────────────────────
if [[ "${HTTP_ONLY}" == "false" ]]; then
    check_container "postgres"    "PostgreSQL"    "pg_isready OK"
    check_container "redis"       "Redis"         "PING → PONG"
    check_container "minio"       "MinIO"         "S3 object store"
    check_container "clickhouse"  "ClickHouse"    "analytics store"
    check_container "qdrant"      "Qdrant"        "vector store"

    if [[ "${QUIET}" == "false" ]]; then
        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo -e "${BOLD}Proxy & Identité${NC}"
        echo "────────────────────────────────────────────────────────────────"
    fi

    check_container "traefik"            "Traefik"
    check_container "authentik-server"   "Authentik Server"
    check_container "authentik-worker"   "Authentik Worker"

    if [[ "${QUIET}" == "false" ]]; then
        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo -e "${BOLD}Applications IA${NC}"
        echo "────────────────────────────────────────────────────────────────"
    fi

    check_container "open-webui"      "Open WebUI"
    check_container "dify-api"        "Dify API"
    check_container "dify-worker"     "Dify Worker"
    check_container "dify-web"        "Dify Web"
    check_container "dify-nginx"      "Dify Nginx"
    check_container "dify-sandbox"    "Dify Sandbox"
    check_container "langfuse-web"    "Langfuse Web"
    check_container "langfuse-worker" "Langfuse Worker"
    check_container "infisical"       "Infisical"
    # Comp AI est optionnel (désactivé par défaut en local : build trop lourd).
    # Ne le compte comme KO que s'il est censé tourner.
    if docker inspect comp-ai &>/dev/null 2>&1; then
        check_container "comp-ai"     "Comp AI"
    elif [[ "${QUIET}" == "false" ]]; then
        printf "  %s  %s  %s\n" "$(status_label WARN)" "$(pad_right "Comp AI" 22)" \
            "Désactivé (optionnel — activer via make build-comp-ai)"
    fi

    if [[ "${QUIET}" == "false" ]]; then
        echo ""
    fi
fi

# ── HTTP endpoints ────────────────────────────────────────────────────────────
if [[ "${QUIET}" == "false" ]]; then
    echo "────────────────────────────────────────────────────────────────"
    echo -e "${BOLD}Endpoints HTTP publics (${PROTOCOL}://${DOMAIN})${NC}"
    echo "────────────────────────────────────────────────────────────────"
fi

# Portail
check_http "Portal"      "${PROTOCOL}://${DOMAIN}/"                    "200" "Page d'accueil"
# Open WebUI
check_http "Open WebUI"  "${PROTOCOL}://chat.${DOMAIN}/"               "200" ""
# Dify
check_http "Dify"        "${PROTOCOL}://dify.${DOMAIN}/"               "200" ""
# Langfuse
check_http "Langfuse"    "${PROTOCOL}://observe.${DOMAIN}/"            "200" ""
# Infisical
check_http "Infisical"   "${PROTOCOL}://secrets.${DOMAIN}/"            "200" ""
# Comp AI (optionnel — vérifié seulement si le conteneur existe)
if docker inspect comp-ai &>/dev/null 2>&1; then
    check_http "Comp AI"     "${PROTOCOL}://compliance.${DOMAIN}/"         "200" ""
fi
# Authentik
check_http "Authentik"   "${PROTOCOL}://auth.${DOMAIN}/api/v3/"        "200" "API Authentik"
# Traefik dashboard (protégé par forwardAuth)
check_http "Traefik"     "${PROTOCOL}://traefik.${DOMAIN}/dashboard/"  "401" "Dashboard (auth)"

# ── Vérifications internes (docker network) ───────────────────────────────────
if [[ "${HTTP_ONLY}" == "false" ]]; then
    if [[ "${QUIET}" == "false" ]]; then
        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo -e "${BOLD}Santé interne (réseau aiws)${NC}"
        echo "────────────────────────────────────────────────────────────────"
    fi

    # Qdrant via son endpoint healthz. L'image Qdrant n'embarque ni curl ni wget, on
    # sonde donc depuis un conteneur outillé du réseau aiws (open-webui a curl).
    QDRANT_HEALTH="$(docker exec open-webui curl -sf http://qdrant:6333/healthz 2>/dev/null | head -c 20 || echo "")"
    if echo "${QDRANT_HEALTH}" | grep -qi "ok\|true\|200\|passed"; then
        status="OK"
    else
        status="KO"
    fi
    RESULTS+=("{\"name\":\"Qdrant (internal)\",\"status\":\"${status}\",\"detail\":\"${QDRANT_HEALTH:-connexion échouée}\"}")
    if [[ "${QUIET}" == "false" ]]; then
        printf "  %s  %s  %s\n" \
            "$(status_label "${status}")" \
            "$(pad_right "Qdrant (internal)" 22)" \
            "${QDRANT_HEALTH:-connexion échouée}"
    fi
    case "${status}" in
        OK)   COUNT_OK=$((COUNT_OK+1)) ;;
        KO)   COUNT_KO=$((COUNT_KO+1)) ;;
    esac
fi

# =============================================================================
# RÉSUMÉ
# =============================================================================
TOTAL=$((COUNT_OK + COUNT_WARN + COUNT_KO))

if [[ "${QUIET}" == "false" ]]; then
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo -e "${BOLD}Résumé :  ${GREEN}${COUNT_OK} OK${NC}  |  ${YELLOW}${COUNT_WARN} WARN${NC}  |  ${RED}${COUNT_KO} KO${NC}  (total: ${TOTAL})"
    echo "════════════════════════════════════════════════════════════════"
    echo ""

    if [[ "${COUNT_KO}" -gt 0 ]]; then
        echo -e "${RED}Des services sont en erreur. Commandes utiles :${NC}"
        echo "  docker compose logs <service>       # voir les logs"
        echo "  docker inspect <container>          # détails du conteneur"
        echo "  docker compose restart <service>    # redémarrer un service"
        echo ""
    fi

    if [[ "${COUNT_WARN}" -gt 0 ]]; then
        echo -e "${YELLOW}Des services sont en avertissement (démarrage en cours ou pas de healthcheck).${NC}"
        echo "  Attendre 30-60s puis relancer : bash scripts/healthcheck.sh"
        echo ""
    fi
fi

# Sortie JSON pour CI/CD (--quiet)
if [[ "${QUIET}" == "true" ]]; then
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"domain\": \"${DOMAIN}\","
    echo "  \"summary\": {\"ok\": ${COUNT_OK}, \"warn\": ${COUNT_WARN}, \"ko\": ${COUNT_KO}, \"total\": ${TOTAL}},"
    echo "  \"services\": ["
    local_sep=""
    for r in "${RESULTS[@]}"; do
        echo "    ${local_sep}${r}"
        local_sep=","
    done
    echo "  ]"
    echo "}"
fi

# Code de sortie : 0 = tout OK ou WARN, 1 = au moins un KO
if [[ "${COUNT_KO}" -gt 0 ]]; then
    exit 1
fi
exit 0
