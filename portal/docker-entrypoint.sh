#!/bin/sh
# docker-entrypoint.sh — Substitution de __DOMAIN__ au démarrage
#
# Variable d'environnement requise :
#   DOMAIN  — domaine de base (ex: ai.example.com ou aiws.localhost)
#             Sans ce-dernier le portail reste fonctionnel avec les URLs littérales __DOMAIN__.
#
# Mécanisme : envsubst remplace __DOMAIN__ dans index.html puis lance nginx.
# Les fichiers .css et .js sont copiés inchangés (pas de __DOMAIN__ dedans).

set -e

# Valeur par défaut si DOMAIN absent (dev local)
DOMAIN="${DOMAIN:-aiws.localhost}"

echo "[portal] DOMAIN=${DOMAIN}"

# Substitution __DOMAIN__ → valeur réelle dans le HTML
# On travaille sur une copie pour ne pas toucher l'image d'origine
if [ -f /usr/share/nginx/html/index.html ]; then
    # envsubst ne comprend pas __DOMAIN__, on utilise sed
    sed -i "s|__DOMAIN__|${DOMAIN}|g" /usr/share/nginx/html/index.html
    echo "[portal] Substitution __DOMAIN__ -> ${DOMAIN} effectuée"
else
    echo "[portal] WARN: index.html introuvable dans /usr/share/nginx/html/"
fi

# Démarrer nginx au premier plan
exec nginx -g "daemon off;"
