# Dockerfile — AI Workspace Portal
#
# Image : nginx:alpine (légère, ~8 MB)
# Expose : port 80 (géré par Traefik pour HTTPS)
#
# Variable d'environnement requise au runtime :
#   DOMAIN  — domaine de base (ex: ai.example.com)
#             Substitue __DOMAIN__ dans index.html via l'entrypoint.
#
# Usage :
#   docker build -t aiws-portal .
#   docker run -e DOMAIN=ai.example.com -p 8080:80 aiws-portal

FROM nginx:alpine

# Métadonnées
LABEL org.opencontainers.image.title="AI Workspace Portal"
LABEL org.opencontainers.image.description="Page d'accueil unifiée de la suite AI Workspace"

# Supprimer la config nginx par défaut
RUN rm -f /etc/nginx/conf.d/default.conf

# Copier la config nginx personnalisée
COPY nginx.conf /etc/nginx/nginx.conf

# Copier les fichiers statiques
COPY index.html  /usr/share/nginx/html/index.html
COPY styles.css  /usr/share/nginx/html/styles.css

# Copier et rendre exécutable l'entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Vérification de santé (utilisée par Docker et Traefik)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost/health || exit 1

EXPOSE 80

# L'entrypoint substitue DOMAIN puis lance nginx
ENTRYPOINT ["/docker-entrypoint.sh"]
