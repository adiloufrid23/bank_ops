# Guide Dynatrace — Monitoring Bank-Ops-Lab

## Qu'est-ce que Dynatrace ?

Dynatrace est une plateforme d'observabilité full-stack (APM, infrastructure, logs, synthetics, RUM). En environnement bancaire, elle fournit la visibilité de bout en bout nécessaire pour garantir les SLAs et détecter les anomalies avant qu'elles n'impactent les clients.

## Pourquoi Dynatrace en banque ?

Les applications bancaires ont des exigences strictes : temps de réponse < 3s, disponibilité 99.9%, traçabilité complète des transactions. Dynatrace permet de monitorer chaque couche (réseau, serveur, application, base de données) et de corréler automatiquement les problèmes grâce à son moteur d'IA Davis.

## Architecture de monitoring

### OneAgent
Agent installé sur chaque serveur (physique, VM, conteneur). Collecte automatiquement les métriques d'infrastructure (CPU, RAM, disque, réseau) et instrumente les applications (Java, .NET, Node.js) sans modification du code.

### ActiveGate
Composant proxy qui route le trafic entre les OneAgents et le cluster Dynatrace. Gère aussi le monitoring Kubernetes et les extensions.

### Davis AI
Moteur d'intelligence artificielle qui détecte automatiquement les anomalies, identifie la cause racine et génère des alertes contextualisées.

## Ce que Dynatrace monitore dans Bank-Ops

### Infrastructure
- CPU, mémoire, disque, réseau de chaque serveur
- Santé des conteneurs Docker
- État du cluster Kubernetes (pods, nodes, namespaces)
- Métriques PostgreSQL (connexions, requêtes lentes, verrous)

### Application
- Temps de réponse des API REST (P50, P95, P99)
- Taux d'erreur par endpoint
- Traces distribuées des transactions bancaires
- Performance WebSphere Liberty (pool JDBC, sessions, threads)

### Processus métier
- Durée du batch quotidien (Autosys)
- Nombre de transactions traitées par minute
- Statut des transferts CFT
- Taux de succès de la réconciliation

### Logs
- Logs applicatifs (Spring Boot, WebSphere)
- Logs batch (`/var/log/bank-ops/batch_*.log`)
- Logs CFT (`/var/log/bank-ops/cft/*.log`)
- Logs Kubernetes (stdout/stderr des pods)

## Configuration dans le projet

### dynatrace-operator.yaml
Déploie l'opérateur Dynatrace sur Kubernetes avec injection automatique du OneAgent dans chaque pod du namespace `bankops`.

### dynatrace-config.yaml
Définit les alerting profiles, les notifications Slack, les métriques personnalisées et les SLOs.

### roles/monitoring/tasks/main.yml
Playbook Ansible qui installe le OneAgent sur les serveurs bare-metal, configure l'ingestion de logs et les métriques custom.

## Alertes configurées

| Alerte | Seuil | Délai | Action |
|---|---|---|---|
| Erreur applicative | > 1% | Immédiat | Slack + Email |
| Temps de réponse | > 3s (P95) | 5 min | Slack |
| Service indisponible | DOWN | Immédiat | Slack + PagerDuty |
| CPU serveur | > 90% | 10 min | Email |
| Disque | > 85% | 15 min | Email |
| Batch en retard | > SLA | Immédiat | Slack + Email |

## SLOs (Service Level Objectives)

| SLO | Cible | Warning | Période |
|---|---|---|---|
| Disponibilité API | 99.9% | 99.95% | Mois glissant |
| Temps de réponse P95 | < 3s | < 2s | Mois glissant |
| Taux de succès batch | 99.5% | 99.8% | Mois glissant |

## Dashboard opérationnel

Le dashboard Bank-Ops affiche en temps réel :
- Le taux de succès des transactions (SLO)
- Le temps de réponse P95 par service
- Le nombre de pods Kubernetes actifs
- L'utilisation CPU/mémoire par conteneur
- Le statut des transferts CFT
- Le résumé des batchs Autosys

## Commandes utiles

```bash
# Vérifier le statut du OneAgent
systemctl status oneagent

# Voir les logs du OneAgent
journalctl -u oneagent -f

# Redémarrer le OneAgent
systemctl restart oneagent

# Vérifier la version installée
/opt/dynatrace/oneagent/agent/tools/lib64/oneagentutil --version

# Tester la connectivité avec le cluster
/opt/dynatrace/oneagent/agent/tools/lib64/oneagentutil --get-server-info
```

## Bonnes pratiques

1. Taguer tous les services avec `app:bankops` et `env:production` pour filtrer facilement.
2. Définir des SLOs réalistes basés sur les données historiques.
3. Configurer Davis AI avec des baselines personnalisées pendant les heures de batch.
4. Utiliser les management zones pour séparer les environnements (staging/production).
5. Exporter les métriques vers un stockage longue durée pour les audits.
6. Créer des dashboards dédiés par équipe (dev, ops, management).
