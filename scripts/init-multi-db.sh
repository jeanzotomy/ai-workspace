#!/bin/sh
# =============================================================================
# scripts/init-multi-db.sh — Initialisation multi-bases PostgreSQL
# =============================================================================
# Monté dans /docker-entrypoint-initdb.d/ du conteneur postgres.
# Exécuté UNE SEULE FOIS à la création du volume (idempotent via IF NOT EXISTS).
#
# Crée 5 bases + 5 users dédiés pour les briques de l'AI Workspace :
#   dify, langfuse, infisical, compai, authentik
#
# Variables d'environnement requises (passées via compose/infra.yml) :
#   AUTHENTIK_DB_USER, AUTHENTIK_DB_PASSWORD, AUTHENTIK_DB_NAME
#   DIFY_DB_USER,      DIFY_DB_PASSWORD,      DIFY_DB_NAME
#   LANGFUSE_DB_USER,  LANGFUSE_DB_PASSWORD,   LANGFUSE_DB_NAME
#   INFISICAL_DB_USER, INFISICAL_DB_PASSWORD,   INFISICAL_DB_NAME
#   COMPAI_DB_USER,    COMPAI_DB_PASSWORD,      COMPAI_DB_NAME
#
# Connexion superuser utilisée par postgres image : POSTGRES_USER / POSTGRES_PASSWORD
# =============================================================================

set -e

# Fonction utilitaire : crée un user + une base, idempotent
create_user_and_db() {
    local user="$1"
    local password="$2"
    local dbname="$3"

    echo "[init-multi-db] Creating user '${user}' and database '${dbname}'..."

    # Créer le user s'il n'existe pas déjà
    psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname postgres <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${user}') THEN
                CREATE ROLE "${user}" WITH LOGIN PASSWORD '${password}';
                RAISE NOTICE 'User ${user} created.';
            ELSE
                -- Mettre à jour le mot de passe au cas où il a changé
                ALTER ROLE "${user}" WITH PASSWORD '${password}';
                RAISE NOTICE 'User ${user} already exists — password updated.';
            END IF;
        END
        \$\$;
EOSQL

    # Créer la base si elle n'existe pas
    psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname postgres <<-EOSQL
        SELECT 'CREATE DATABASE "${dbname}" OWNER "${user}" ENCODING ''UTF8'' LC_COLLATE ''en_US.UTF-8'' LC_CTYPE ''en_US.UTF-8'''
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${dbname}')
        \gexec
EOSQL

    # GRANT CONNECT + tous les privilèges sur la base
    psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname postgres <<-EOSQL
        GRANT ALL PRIVILEGES ON DATABASE "${dbname}" TO "${user}";
EOSQL

    # Activer les extensions nécessaires dans la base
    psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${dbname}" <<-EOSQL
        -- uuid-ossp : génération UUID v4 (utilisée par Dify, Langfuse, Authentik)
        CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

        -- pgcrypto : fonctions cryptographiques (Infisical, Authentik)
        CREATE EXTENSION IF NOT EXISTS "pgcrypto";

        -- pg_trgm : recherche fuzzy (Langfuse)
        CREATE EXTENSION IF NOT EXISTS "pg_trgm";

        -- Donner ownership du schéma public au user dédié
        ALTER SCHEMA public OWNER TO "${user}";
        GRANT ALL ON SCHEMA public TO "${user}";
EOSQL

    echo "[init-multi-db] Done: user '${user}' + database '${dbname}'."
}

# NOTE sur pgvector :
# Dify v1.14.2 utilise Qdrant comme vector store par défaut (configuré dans compose/dify.yml).
# pgvector n'est pas requis dans cette configuration.
# Si vous souhaitez basculer Dify sur pgvector comme vector store, ajoutez :
#   CREATE EXTENSION IF NOT EXISTS vector;
# dans le bloc create_user_and_db pour la base "dify" ET changez VECTOR_STORE=pgvector dans dify.yml.

echo "====================================================================="
echo "[init-multi-db] Starting AI Workspace multi-database initialization"
echo "====================================================================="

# ── Authentik ────────────────────────────────────────────────────────────────
create_user_and_db \
    "${AUTHENTIK_DB_USER:-authentik}" \
    "${AUTHENTIK_DB_PASSWORD}" \
    "${AUTHENTIK_DB_NAME:-authentik}"

# ── Dify ─────────────────────────────────────────────────────────────────────
create_user_and_db \
    "${DIFY_DB_USER:-dify}" \
    "${DIFY_DB_PASSWORD}" \
    "${DIFY_DB_NAME:-dify}"

# ── Langfuse ─────────────────────────────────────────────────────────────────
create_user_and_db \
    "${LANGFUSE_DB_USER:-langfuse}" \
    "${LANGFUSE_DB_PASSWORD}" \
    "${LANGFUSE_DB_NAME:-langfuse}"

# ── Infisical ────────────────────────────────────────────────────────────────
create_user_and_db \
    "${INFISICAL_DB_USER:-infisical}" \
    "${INFISICAL_DB_PASSWORD}" \
    "${INFISICAL_DB_NAME:-infisical}"

# ── Comp AI ──────────────────────────────────────────────────────────────────
create_user_and_db \
    "${COMPAI_DB_USER:-compai}" \
    "${COMPAI_DB_PASSWORD}" \
    "${COMPAI_DB_NAME:-compai}"

echo "====================================================================="
echo "[init-multi-db] All databases initialized successfully."
echo ""
echo "  Databases created:"
echo "    - ${AUTHENTIK_DB_NAME:-authentik}  (user: ${AUTHENTIK_DB_USER:-authentik})"
echo "    - ${DIFY_DB_NAME:-dify}        (user: ${DIFY_DB_USER:-dify})"
echo "    - ${LANGFUSE_DB_NAME:-langfuse}   (user: ${LANGFUSE_DB_USER:-langfuse})"
echo "    - ${INFISICAL_DB_NAME:-infisical}  (user: ${INFISICAL_DB_USER:-infisical})"
echo "    - ${COMPAI_DB_NAME:-compai}     (user: ${COMPAI_DB_USER:-compai})"
echo "====================================================================="
