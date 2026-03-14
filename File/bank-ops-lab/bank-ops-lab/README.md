# 🏦 Bank-Ops-Lab

> Plateforme bancaire simulée — projet DevOps / Ops couvrant l'ensemble de la stack technique d'un environnement de production bancaire.

## 🎯 Objectif

Ce projet démontre la maîtrise des technologies suivantes dans un contexte bancaire réaliste :

| Technologie | Rôle dans le projet |
|---|---|
| **Linux (RHEL/Ubuntu)** | Socle système, administration serveurs |
| **Shell (Bash)** | Scripts de batch, automatisation, monitoring |
| **CFT (Axway Transfer)** | Transfert sécurisé de fichiers bancaires |
| **WebSphere / Liberty** | Serveur d'application Java EE |
| **Autosys (CA Workload)** | Ordonnancement des jobs et dépendances |
| **Dynatrace** | Monitoring APM, alerting, dashboards |
| **Docker** | Conteneurisation des services |
| **Kubernetes** | Orchestration, scaling, haute disponibilité |
| **Ansible** | Provisioning, configuration, déploiement |
| **Cloud privé** | Infrastructure on-premise conteneurisée |

## 📁 Structure du projet

```
bank-ops-lab/
├── README.md                    # Ce fichier
├── docs/                        # Documentation détaillée
│   ├── ARCHITECTURE.md          # Architecture technique
│   ├── AUTOSYS_GUIDE.md         # Guide ordonnancement
│   ├── CFT_GUIDE.md             # Guide transferts fichiers
│   ├── DYNATRACE_GUIDE.md       # Guide monitoring
│   └── RUNBOOK.md               # Procédures d'exploitation
├── scripts/
│   ├── shell/                   # Scripts Bash d'exploitation
│   │   ├── health_check.sh      # Vérification santé services
│   │   ├── log_rotate.sh        # Rotation et archivage logs
│   │   ├── batch_processing.sh  # Traitement batch bancaire
│   │   └── backup_db.sh         # Sauvegarde base de données
│   ├── autosys/                 # Jobs Autosys (JIL)
│   │   ├── daily_batch.jil      # Batch quotidien
│   │   ├── monthly_close.jil    # Clôture mensuelle
│   │   └── file_transfer.jil    # Orchestration transferts
│   └── cft/                     # Configuration CFT
│       ├── partners.cfg         # Définition partenaires
│       ├── transfer_daily.cfg   # Transferts quotidiens
│       └── monitor_transfers.sh # Supervision transferts
├── docker/
│   ├── docker-compose.yml       # Stack complète locale
│   ├── websphere/               # Image WebSphere Liberty
│   │   ├── Dockerfile
│   │   └── server.xml
│   ├── api/                     # API REST Spring Boot
│   │   └── Dockerfile
│   └── nginx/                   # Reverse proxy
│       ├── Dockerfile
│       └── nginx.conf
├── k8s/
│   ├── base/                    # Manifestes Kubernetes
│   │   ├── namespace.yaml
│   │   ├── deployment-api.yaml
│   │   ├── deployment-websphere.yaml
│   │   ├── service-api.yaml
│   │   ├── service-websphere.yaml
│   │   ├── ingress.yaml
│   │   ├── hpa.yaml
│   │   └── configmap.yaml
│   └── monitoring/              # Stack monitoring
│       ├── dynatrace-operator.yaml
│       └── dynatrace-config.yaml
└── ansible/
    ├── ansible.cfg
    ├── inventory/
    │   ├── production.ini
    │   └── staging.ini
    ├── playbooks/
    │   ├── deploy_app.yml       # Déploiement applicatif
    │   ├── setup_infra.yml      # Provisioning infra
    │   └── rolling_update.yml   # Mise à jour sans coupure
    └── roles/
        ├── websphere/           # Rôle WebSphere
        ├── docker/              # Rôle Docker/K8s
        └── monitoring/          # Rôle Dynatrace
```

## 🚀 Démarrage rapide

### Prérequis
- Linux (Ubuntu 22.04+ ou RHEL 8+)
- Docker & Docker Compose
- kubectl + accès cluster K8s (minikube pour le dev)
- Ansible 2.14+
- Java 17+ (pour WebSphere Liberty)

### 1. Lancer la stack locale avec Docker
```bash
cd docker/
docker-compose up -d
```

### 2. Provisionner avec Ansible
```bash
cd ansible/
ansible-playbook -i inventory/staging.ini playbooks/setup_infra.yml
```

### 3. Déployer sur Kubernetes
```bash
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/
kubectl apply -f k8s/monitoring/
```

### 4. Vérifier la santé
```bash
./scripts/shell/health_check.sh
```

## 📊 Scénarios d'exploitation simulés

1. **Batch quotidien** : Autosys déclenche les scripts Shell → traitement des transactions → génération des rapports
2. **Transfert fichiers** : CFT envoie/reçoit les fichiers SEPA vers les partenaires bancaires
3. **Déploiement Blue/Green** : Ansible orchestre un rolling update sans coupure de service
4. **Incident monitoring** : Dynatrace détecte une anomalie → alerte → runbook automatisé
5. **Scaling** : Kubernetes HPA ajuste les réplicas selon la charge

## 📝 Licence

Projet personnel à but démonstratif.
