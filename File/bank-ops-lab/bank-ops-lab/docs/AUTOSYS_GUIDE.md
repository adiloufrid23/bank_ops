# Guide Autosys — Ordonnancement Bank-Ops-Lab

## Qu'est-ce qu'Autosys ?

Autosys (CA Workload Automation) est un ordonnanceur de jobs utilisé dans les environnements bancaires pour planifier, séquencer et surveiller les traitements batch. Il remplace les crontabs par un système centralisé avec gestion des dépendances, alertes et reprise sur erreur.

## Concepts clés

### Job
Unité de travail élémentaire. Un job exécute une commande sur une machine cible. Chaque job possède un statut : `STARTING`, `RUNNING`, `SUCCESS`, `FAILURE`, `ON_HOLD`, `ON_ICE`, `TERMINATED`.

### Box
Conteneur logique regroupant plusieurs jobs. Un box a son propre statut qui dépend de ses jobs enfants. Il permet de définir des conditions de déclenchement globales (date, heure, calendrier).

### JIL (Job Information Language)
Langage déclaratif pour définir les jobs. Chaque fichier `.jil` décrit les propriétés d'un ou plusieurs jobs : commande, machine, conditions, dépendances, alarmes.

### Conditions de dépendance
Un job peut dépendre du succès, de l'échec ou de la fin d'un autre job :
- `success(JOB_NAME)` — le job parent doit avoir réussi
- `failure(JOB_NAME)` — le job parent doit avoir échoué
- `done(JOB_NAME)` — le job parent doit être terminé (succès ou échec)

## Fichiers JIL du projet

### daily_batch.jil — Batch quotidien

Ce fichier définit la chaîne de traitement quotidienne :

```
BANK_DAILY_BOX (Box — déclenchement à 02:00 du lundi au vendredi)
├── BANK_DAILY_START        → Health check des services
├── BANK_RECEIVE_FILES      → Réception fichiers via CFT (timeout 30min)
├── BANK_VALIDATE_FILES     → Validation dry-run
├── BANK_PROCESS_TX         → Traitement des transactions
├── BANK_RECONCILIATION     → Réconciliation des soldes
├── BANK_GENERATE_REPORTS   → Génération des rapports PDF
├── BANK_SEND_FILES         → Envoi vers partenaires via CFT
└── BANK_DAILY_END          → Notification Slack/email
```

Chaque job dépend du succès du précédent (`condition: success(...)`).

### monthly_close.jil — Clôture mensuelle

Exécuté le dernier jour ouvré du mois à 22:00. Séquence : gel des comptes, calcul des intérêts, rapport réglementaire COREP/FINREP, dégel des comptes.

## Commandes Autosys utiles

```bash
# Voir le statut d'un job
autorep -j BANK_DAILY_BOX -s

# Voir les détails d'un job
autorep -j BANK_PROCESS_TX -d

# Forcer le démarrage d'un job
sendevent -E FORCE_STARTJOB -J BANK_DAILY_BOX

# Mettre un job en attente
sendevent -E JOB_ON_HOLD -J BANK_PROCESS_TX

# Relâcher un job en attente
sendevent -E JOB_OFF_HOLD -J BANK_PROCESS_TX

# Mettre un job "on ice" (désactivé mais visible)
sendevent -E JOB_ON_ICE -J BANK_SEND_FILES

# Relancer un job en échec
sendevent -E FORCE_STARTJOB -J BANK_RECEIVE_FILES

# Charger un fichier JIL
jil < daily_batch.jil

# Voir l'historique d'exécution
autorep -j BANK_DAILY_BOX -r 7
```

## Bonnes pratiques en environnement bancaire

1. Toujours utiliser des `max_run_alarm` pour détecter les jobs qui dépassent leur durée normale.
2. Configurer `alarm_if_fail: 1` sur tous les jobs critiques.
3. Utiliser `n_retrys` pour les jobs réseau (transferts CFT, appels API) qui peuvent échouer temporairement.
4. Documenter chaque job avec le champ `description`.
5. Utiliser des calendriers personnalisés (`run_calendar`) pour les jours fériés et les week-ends.
6. Stocker les logs dans des fichiers datés (`std_out_file`, `std_err_file`).
7. Tester les JIL en staging avant de les charger en production.
