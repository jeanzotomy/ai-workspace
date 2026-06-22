#!/usr/bin/env bash
# =============================================================================
# scripts/sync-oidc-secrets.sh
# =============================================================================
# Reporte automatiquement les client_id / client_secret générés par Authentik
# (providers OIDC du blueprint ai-workspace) dans le fichier .env, puis recrée
# les services concernés.
#
# À lancer APRÈS que le blueprint Authentik a été appliqué (providers créés).
#   bash scripts/sync-oidc-secrets.sh          # met à jour .env + recrée les services
#   bash scripts/sync-oidc-secrets.sh --print  # affiche seulement, ne modifie rien
#
# Idempotent : relançable sans danger (remplace les valeurs existantes).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT}/.env"
PRINT_ONLY=false
[[ "${1:-}" == "--print" ]] && PRINT_ONLY=true

# provider Authentik  ->  préfixe variable .env
declare -A PROVIDERS=(
  [provider-open-webui]=OPENWEBUI_OIDC
  [provider-langfuse]=LANGFUSE_OIDC
  [provider-comp-ai]=COMPAI_OIDC
)

# Récupère (client_id|client_secret) d'un provider depuis la base Authentik.
fetch_creds() {
  local provider="$1"
  docker exec postgres psql -U authentik -d authentik -t -A -F'|' -c \
    "SELECT o.client_id, o.client_secret
       FROM authentik_providers_oauth2_oauth2provider o
       JOIN authentik_core_provider cp ON cp.id = o.provider_ptr_id
      WHERE cp.name = '${provider}';" 2>/dev/null | head -n1
}

# Remplace (ou ajoute) KEY=VALUE dans .env.
set_env() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" "${ENV_FILE}"; then
    # délimiteur | pour éviter les collisions avec / dans les secrets
    sed -i "s|^${key}=.*|${key}=${val}|" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${val}" >> "${ENV_FILE}"
  fi
}

changed_services=()
for provider in "${!PROVIDERS[@]}"; do
  prefix="${PROVIDERS[$provider]}"
  creds="$(fetch_creds "${provider}")"
  if [[ -z "${creds}" || "${creds}" != *"|"* ]]; then
    echo "⚠  ${provider} : introuvable dans Authentik (blueprint appliqué ?) — ignoré"
    continue
  fi
  cid="${creds%%|*}"
  csecret="${creds#*|}"
  echo "✓ ${provider} -> ${prefix}_CLIENT_ID=${cid:0:8}…  (secret ${#csecret} chars)"
  if [[ "${PRINT_ONLY}" == "false" ]]; then
    set_env "${prefix}_CLIENT_ID" "${cid}"
    set_env "${prefix}_CLIENT_SECRET" "${csecret}"
  fi
done

if [[ "${PRINT_ONLY}" == "true" ]]; then
  echo "(--print : .env non modifié)"
  exit 0
fi

echo ""
echo "→ Recréation des services consommant l'OIDC (open-webui, langfuse-web)…"
( cd "${ROOT}" && docker compose up -d open-webui langfuse-web )
echo "✓ Terminé. Vérifier le bouton « Sign in with Authentik » sur chat.\${DOMAIN}."
