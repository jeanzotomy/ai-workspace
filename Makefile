# =============================================================================
# AI Workspace — Makefile
# Usage : make help (affiche toutes les cibles)
# =============================================================================

SHELL := /bin/bash
COMPOSE := docker compose

# Couleurs
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m

.DEFAULT_GOAL := help

# -----------------------------------------------------------------------------
.PHONY: help
help: ## Affiche cette aide
	@echo ""
	@echo "  AI Workspace — Commandes disponibles"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-18s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# -----------------------------------------------------------------------------
.PHONY: bootstrap
bootstrap: ## Génère les secrets, crée .env, initialise les volumes
	@echo "$(YELLOW)Bootstrap de l'environnement...$(NC)"
	@test -f .env && echo "$(YELLOW)⚠  .env existe déjà — supprimez-le pour réinitialiser$(NC)" || bash scripts/bootstrap.sh
	@echo "$(GREEN)Bootstrap terminé. Lancez 'make up' pour démarrer.$(NC)"

# -----------------------------------------------------------------------------
.PHONY: up
up: ## Démarre tous les services en arrière-plan
	@echo "$(GREEN)Démarrage des services...$(NC)"
	@docker network inspect aiws >/dev/null 2>&1 || docker network create --driver bridge aiws
	$(COMPOSE) up -d
	@echo "$(GREEN)Services démarrés. Vérifiez avec 'make ps' ou 'make health'.$(NC)"

# -----------------------------------------------------------------------------
.PHONY: down
down: ## Arrête tous les services (conserve les volumes)
	@echo "$(YELLOW)Arrêt des services...$(NC)"
	$(COMPOSE) down
	@echo "$(GREEN)Services arrêtés.$(NC)"

# -----------------------------------------------------------------------------
.PHONY: restart
restart: ## Redémarre tous les services
	@echo "$(YELLOW)Redémarrage des services...$(NC)"
	$(COMPOSE) restart
	@echo "$(GREEN)Services redémarrés.$(NC)"

# -----------------------------------------------------------------------------
.PHONY: logs
logs: ## Suit les logs de tous les services (Ctrl+C pour quitter)
	$(COMPOSE) logs -f

# -----------------------------------------------------------------------------
.PHONY: logs-%
logs-%: ## Suit les logs d'un service spécifique : make logs-traefik
	$(COMPOSE) logs -f $*

# -----------------------------------------------------------------------------
.PHONY: ps
ps: ## Affiche l'état de tous les containers
	$(COMPOSE) ps

# -----------------------------------------------------------------------------
.PHONY: pull
pull: ## Télécharge les dernières images (sans redémarrer)
	@echo "$(YELLOW)Téléchargement des images...$(NC)"
	$(COMPOSE) pull
	@echo "$(GREEN)Images mises à jour. Lancez 'make restart' pour les appliquer.$(NC)"

# -----------------------------------------------------------------------------
.PHONY: health
health: ## Vérifie la santé de tous les services
	@echo "$(YELLOW)Vérification de la santé des services...$(NC)"
	@bash scripts/healthcheck.sh

# -----------------------------------------------------------------------------
.PHONY: clean
clean: ## ⚠️  DESTRUCTIF — Supprime les containers ET les volumes (demande confirmation)
	@echo "$(RED)⚠️  ATTENTION : Cette commande supprime TOUS les volumes (données perdues !).$(NC)"
	@echo "$(RED)Tapez 'oui' pour confirmer :$(NC)"
	@read -r CONFIRM && [ "$$CONFIRM" = "oui" ] || (echo "$(GREEN)Annulé.$(NC)" && exit 1)
	@echo "$(RED)Suppression en cours...$(NC)"
	$(COMPOSE) down -v --remove-orphans
	@echo "$(RED)Volumes supprimés.$(NC)"

# -----------------------------------------------------------------------------
.PHONY: build-comp-ai
build-comp-ai: ## Construit l'image Comp AI depuis les sources (vendor/comp)
	@echo "$(YELLOW)Construction de l'image Comp AI...$(NC)"
	@test -d vendor/comp || (echo "$(RED)vendor/comp absent — lancez 'make bootstrap'$(NC)" && exit 1)
	$(COMPOSE) build comp-ai
	@echo "$(GREEN)Image Comp AI construite.$(NC)"

# -----------------------------------------------------------------------------
.PHONY: exec-%
exec-%: ## Ouvre un shell dans un container : make exec-postgres
	$(COMPOSE) exec $* /bin/sh

# -----------------------------------------------------------------------------
.PHONY: config
config: ## Valide la configuration docker-compose (debug)
	$(COMPOSE) config

# -----------------------------------------------------------------------------
.PHONY: status
status: ps health ## Alias : état + santé

# -----------------------------------------------------------------------------
.PHONY: update
update: pull restart ## Met à jour les images et redémarre
