# Architecture technique — Bank-Ops-Lab

## Vue d'ensemble

Ce projet simule l'environnement de production d'une application bancaire avec les contraintes suivantes :
- Haute disponibilité (99.9% SLA)
- Sécurité renforcée (chiffrement, audit trail)
- Traçabilité complète des opérations
- Ordonnancement et transferts de fichiers automatisés

## Couches de l'architecture

### 1. Couche Ordonnancement (Autosys)

Autosys (CA Workload Automation) orchestre l'ensemble des traitements batch :

- **Jobs quotidiens** : Réconciliation des transactions, génération des relevés
- **Jobs mensuels** : Clôture comptable, reporting réglementaire
- **Dépendances** : Les jobs respectent un graphe de dépendances (ex: le relevé ne démarre qu'après la réconciliation)
- **Alerting** : Notification en cas d'échec ou de dépassement de SLA

Les fichiers JIL (Job Information Language) définissent chaque job avec ses conditions, horaires et dépendances.

### 2. Couche Traitement (Shell / Linux)

Les scripts Bash s'exécutent sur des serveurs Linux (RHEL 8) et réalisent :

- **Traitement batch** : Parsing de fichiers CSV/XML, calculs, agrégations
- **Health checks** : Vérification de la disponibilité des services
- **Rotation des logs** : Archivage et compression automatique
- **Sauvegardes** : Dump et transfert sécurisé des bases de données

Bonnes pratiques appliquées : `set -euo pipefail`, logging structuré, codes retour standardisés.

### 3. Couche Transfert (CFT / Axway)

CFT (Cross File Transfer) gère les échanges sécurisés :

- **Partenaires** : Banque centrale, chambres de compensation, partenaires SEPA
- **Protocoles** : PeSIT, SFTP avec chiffrement TLS 1.3
- **Monitoring** : Suivi temps réel des transferts, alertes en cas d'échec
- **Reprise** : Mécanisme de retry automatique avec checkpoint

### 4. Couche Application (WebSphere Liberty)

WebSphere Liberty Profile héberge l'application Java EE :

- **Fonctionnalités** : API de gestion des comptes, virements, relevés
- **Configuration** : server.xml avec datasources, JMS, sécurité
- **Clustering** : Plusieurs instances derrière un load balancer
- **Session** : Réplication de session pour la haute disponibilité

### 5. Couche Conteneurisation (Docker + Kubernetes)

L'ensemble des services est conteneurisé :

**Docker** :
- Images optimisées (multi-stage builds)
- Docker Compose pour le développement local
- Registry privé pour les images

**Kubernetes** :
- Namespace dédié par environnement (dev, staging, prod)
- Deployments avec stratégie RollingUpdate
- Services ClusterIP + Ingress Controller
- HPA (Horizontal Pod Autoscaler) basé sur CPU/mémoire
- ConfigMaps et Secrets pour la configuration

### 6. Couche Infrastructure as Code (Ansible)

Ansible automatise le provisioning et les déploiements :

- **Rôles** : websphere, docker, monitoring (réutilisables)
- **Playbooks** : setup_infra, deploy_app, rolling_update
- **Inventaires** : staging et production séparés
- **Vault** : Chiffrement des secrets (mots de passe, clés)

### 7. Couche Monitoring (Dynatrace)

Dynatrace assure l'observabilité de bout en bout :

- **APM** : Traçage des transactions applicatives
- **Infrastructure** : Métriques CPU, mémoire, disque, réseau
- **Synthetics** : Tests de disponibilité automatisés
- **Alerting** : Seuils personnalisés, notification Slack/email
- **Dashboards** : Vue unifiée de la santé de la plateforme

## Flux type : traitement batch quotidien

```
[Autosys] → déclenche → [Shell: batch_processing.sh]
    → lit les fichiers reçus via [CFT]
    → traite les transactions
    → écrit les résultats dans [WebSphere DB]
    → génère les fichiers de sortie
    → [CFT] envoie vers les partenaires
    → [Dynatrace] monitore chaque étape
    → [Autosys] valide la fin du job
```
