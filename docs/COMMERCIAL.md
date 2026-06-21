# AI Workspace — Dossier commercial

> Ce document présente la proposition de valeur, le modèle économique et le
> go-to-market d'une offre de service construite autour d'AI Workspace.
> Les chiffres sont des **projections indicatives** basées sur des hypothèses
> de marché ; ils ne constituent pas des garanties de revenus.

---

## 1. Proposition de valeur

### Le problème

Les organisations qui adoptent des LLM en entreprise font face à trois obstacles :

1. **Coût** : Azure OpenAI Studio + Datadog LLM coûtent 5 000 à 50 000 €/mois pour
   une utilisation intensive (tokens + observabilité + stockage).
2. **Souveraineté** : les données (prompts, documents, historiques) transitent par des
   serveurs cloud étrangers — problématique pour les secteurs réglementés et les
   gouvernements.
3. **Fragmentation** : chat, orchestration, observabilité, gestion des secrets et
   conformité sont des produits séparés, sans intégration native.

### La solution

AI Workspace est une suite IA self-hosted pré-intégrée : cinq briques OSS éprouvées
(Dify, Open WebUI, Langfuse, Infisical, Comp AI) orchestrées par un docker-compose
unifié, derrière un reverse proxy TLS (Traefik) et un IdP SSO (Authentik).

L'intégrateur ou l'ESN déploie la suite sur la VM du client en moins d'une journée,
assure la maintenance mensuelle, et facture un abonnement récurrent.

### Bénéfices chiffrés

| Dimension | Cloud managé (estimation) | AI Workspace self-hosted |
|---|---|---|
| Coût infra mensuel (25 users, 10M tokens) | 8 000–15 000 €/mois | 400–900 €/mois (VM + bande passante) |
| Souveraineté données | Non (cloud étranger) | Oui (VM cliente) |
| Conformité RGPD | Partielle (DPA à signer) | Native (données locales) |
| Observabilité LLM | Payante séparément | Incluse (Langfuse) |
| Gestion secrets | Non intégrée | Incluse (Infisical) |
| Conformité SOC2/ISO 27001 | Non intégrée | Incluse (Comp AI) |

Gain estimé sur 12 mois pour un client Business (25 users) : **70 000–170 000 €**
par rapport à un empilement de services cloud équivalents.

---

## 2. Offre et pricing

### Abonnements mensuels (run)

| Plan | Prix/mois | Utilisateurs | Tokens inclus | Support |
|---|---|---|---|---|
| **Starter** | 499 € | 5 | 1M | Email (48h) |
| **Business** | 1 499 € | 25 | 10M | Email + chat (24h) |
| **Enterprise** | 4 999 € | Illimité | Illimité | Dédié (4h) |

> Les tokens mentionnés sont des quotas de suivi (alertes Langfuse) ; le coût réel
> des API LLM (OpenAI, Anthropic, Mistral) est supporté directement par le client
> selon sa consommation.

### Prestations one-time (setup)

| Prestation | Fourchette | Inclus |
|---|---|---|
| **Setup standard** | 2 000–4 000 € | Déploiement VM, DNS, TLS, bootstrap, SSO Authentik de base |
| **Setup avancé** | 4 000–8 000 € | Setup + intégration LDAP/AD, blueprints Authentik custom, modèles locaux (Ollama), première app Dify |
| **Formation équipes IA** | 1 000–3 000 €/session | Prise en main Dify, Langfuse, bonnes pratiques prompts, sécurité LLM |

### Surcoûts courants

- Modèles locaux (GPU dédié) : selon configuration matérielle client
- SLA renforcé (99,9 % uptime garanti) : +500 €/mois
- Audit de conformité RGPD + rapport Comp AI : 1 500–3 000 € one-time

---

## 3. Économie unitaire

> Hypothèses : intégrateur solo ou petite équipe (1–3 personnes techniques).
> Chiffres hors taxes. Projections, pas des garanties.

### Structure de coûts opérationnels (par client)

| Poste | Mensuel estimé |
|---|---|
| Temps run & maintenance (2–4h/mois @ 100 €/h) | 200–400 € |
| Monitoring, alertes, sauvegardes | 50–100 € |
| Support client | 50–200 € selon plan |
| **Total charges opérationnelles** | **300–700 €/mois** |

### Marge brute indicative par plan

| Plan | Revenu | Charges op. estimées | Marge brute |
|---|---|---|---|
| Starter (499 €) | 499 € | 300–400 € | 100–200 € (~25–40 %) |
| Business (1 499 €) | 1 499 € | 400–600 € | 900–1 100 € (~60–70 %) |
| Enterprise (4 999 €) | 4 999 € | 600–900 € | 4 100–4 400 € (~82–88 %) |

> La marge augmente fortement avec la montée en plan : l'effort opérationnel
> croît peu (même stack, même procédures) tandis que le revenu triple.

### Trajectoire de revenus cibles

| Jalon | Clients | Mix plan | Revenu mensuel récurrent |
|---|---|---|---|
| Mois 3 | 3 clients | 2 Starter + 1 Business | ~2 500 € |
| Mois 6 (break-even) | 5 clients | 2 Starter + 2 Business + 1 Enterprise | ~10 500 € |
| Mois 12 | 10 clients | mix | ~20 000–40 000 € |
| Mois 18 | 20–30 clients | mix | ~40 000–80 000 € |

Break-even estimé au **mois 4–6** avec 5+ clients actifs, en supposant des charges
fixes de structure de 3 000–5 000 €/mois (personnes, outils, cloud de staging).

Les revenus setup (2 000–8 000 € par client) améliorent la trésorerie initiale
mais ne doivent pas être inclus dans le MRR (revenus non récurrents).

---

## 4. Cibles et segments

### Segments primaires (France, Europe)

**ESN et cabinets de conseil IT**
- Revendent la suite à leurs clients comme offre packagée « IA souveraine »
- Modèle : intégration + run externalisé
- Décideur : directeur de pratique IA ou CTO

**Départements IT en entreprise (500+ salariés)**
- Adoption interne de LLM sans exposer les données au cloud
- Conformité DPO/RSSI facilitée (données locales, Comp AI)
- Décideur : DSI, RSSI, DPO

**Intégrateurs spécialisés secteur public**
- Conformité RGPD et souveraineté numérique comme critères d'appel d'offres
- Décideur : chef de projet, direction des systèmes d'information

### Opportunité Afrique francophone

L'Afrique francophone représente une opportunité de premier plan pour plusieurs raisons :

**Gouvernements et ministères**
- Besoin d'IA souveraine (données nationales hors cloud étranger)
- Résumé automatique de documents officiels, traduction vers langues locales
- Absence d'alternative locale crédible à ce prix

**Banques UEMOA et institutions financières**
- Analyse documentaire, KYC automatisé (pièces d'identité, justificatifs)
- Conformité BCEAO et protection des données clients
- Coût 10× inférieur à Azure OpenAI managé — critique sur des marchés à marges serrées

**Universités et établissements d'enseignement supérieur**
- Assistants pédagogiques en langues locales (wolof, mooré, dioula, etc.)
- Infrastructure self-hosted sur serveurs campus (contraintes de bande passante)

**Ministères et organisations internationales**
- Traitement de rapports, synthèse de réunions, extraction d'information
- Confidentialité des travaux diplomatiques ou de politique publique

> L'argument souveraineté + coût est particulièrement fort dans ce contexte :
> les alternatives cloud (Azure, AWS, GCP) sont perçues comme dépendances
> technologiques étrangères, et leurs prix sont prohibitifs rapportés au
> pouvoir d'achat local des institutions.

---

## 5. Argumentaire concurrentiel

### vs Azure OpenAI Studio + Datadog LLM

| Critère | Azure OpenAI + Datadog | AI Workspace |
|---|---|---|
| Coût mensuel (25 users, 10M tokens) | 8 000–15 000 € | 400–900 € infra + abonnement intégrateur |
| Souveraineté données | Non — cloud Microsoft | Oui — VM cliente |
| Conformité RGPD | DPA à signer, données hors EU possibles | Native — données 100 % locales |
| Dépendance fournisseur | Fort lock-in (propriétaire) | Briques OSS, stack migreable |
| Observabilité intégrée | Datadog (payant séparé) | Langfuse (inclus) |
| Gestion secrets | Azure Key Vault (payant séparé) | Infisical (inclus) |
| Conformité SOC2/ISO 27001 | Non intégrée | Comp AI (inclus) |
| Modèles locaux (Ollama) | Non | Oui (via Dify + Open WebUI) |
| Déploiement | SaaS managé | Self-hosted (VM) |

**L'argument principal :** pour une organisation qui traite des données sensibles
(données personnelles, secrets industriels, données réglementées), le choix n'est
pas seulement économique — c'est une question de conformité et de contrôle.
AI Workspace répond aux deux.

### Limites honnêtes

- **Complexité opérationnelle** : une suite self-hosted nécessite des compétences
  DevOps (Docker, Linux, DNS, TLS). C'est précisément le rôle de l'intégrateur.
- **Mises à jour** : les briques OSS évoluent rapidement. L'intégrateur doit
  maintenir une procédure de mise à jour testée.
- **SLA garanti** : un cloud managé offre des SLA contractuels natifs. En self-hosted,
  le SLA dépend de la VM cliente et de la procédure de l'intégrateur.

---

## 6. Modèle de delivery

### Phase 1 — Setup (semaines 1–3)

1. Audit de l'infrastructure existante (VM, DNS, politique sécurité)
2. Déploiement AI Workspace (`make bootstrap` + `make up`)
3. Configuration DNS wildcard et certificats TLS
4. Configuration SSO Authentik (blueprints OIDC)
5. Première app Dify + configuration Langfuse + injection secrets Infisical
6. Formation équipe client (demi-journée)
7. Livraison documentation d'exploitation

### Phase 2 — Run mensuel

- Surveillance santé services (`make health`, alertes)
- Application des mises à jour OSS (tests en staging, déploiement planifié)
- Support utilisateurs selon plan (email/chat)
- Rapport mensuel : usage tokens, coûts, incidents, recommandations

### Phase 3 — Evolution

- Ajout de modèles locaux (Ollama + GPU)
- Développement d'apps Dify supplémentaires (workflows métier)
- Intégrations sur mesure (connecteurs SI, webhooks)
- Audit conformité annuel (Comp AI + rapport RGPD)

---

## 7. Risques et mitigations

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| **Brique OSS abandonnée** (ex: Dify change de licence) | Faible | Élevé | Architecture modulaire — remplacement d'une brique sans refaire toute la suite |
| **Mise à jour casse la configuration** | Moyen | Moyen | Staging systématique, tests health avant prod, rollback documenté |
| **Client sans compétences DevOps internes** | Élevé | Faible | Pris en charge par l'intégrateur (modèle run externalisé) |
| **Concurrence cloud qui baisse les prix** | Moyen | Moyen | Argument souveraineté + conformité inchangé, pas seulement le prix |
| **Conformité RGPD insuffisante** (mauvaise config) | Faible | Critique | Checklist livraison, Comp AI configuré dès le setup, DPA client documenté |
| **Dépendance à un seul intégrateur** (bus factor) | Moyen | Élevé | Documentation exhaustive, runbooks, transfert de compétences client |
| **Capacité de mise à l'échelle** (trop de clients) | Moyen | Moyen | Automatisation progressive (Ansible/Terraform), recrutement ou sous-traitance |

---

## 8. Hypothèses et limites du modèle

Les projections de revenus et marges présentées dans ce document reposent sur
des hypothèses qui doivent être validées sur le terrain :

- Tarifs de vente acceptés par le marché cible (à valider par devis réels)
- Temps opérationnel réel par client (à mesurer sur les premiers déploiements)
- Taux d'acquisition client (dépend du canal commercial et de la réputation)
- Coût réel de la structure (selon que l'intégrateur est solo ou en équipe)

**Ces chiffres sont des estimations, pas des garanties.**
Ajuster le modèle dès les premiers retours terrain.
