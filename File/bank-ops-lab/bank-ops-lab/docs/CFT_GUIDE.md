# Guide CFT — Transferts de fichiers Bank-Ops-Lab

## Qu'est-ce que CFT ?

CFT (Cross File Transfer), produit Axway, est la solution standard de transfert de fichiers dans le secteur bancaire français et européen. Il assure des échanges sécurisés, fiables et traçables entre partenaires financiers.

## Pourquoi CFT en banque ?

Les banques échangent quotidiennement des milliers de fichiers avec leurs partenaires : virements SEPA, prélèvements, relevés de compte, rapports réglementaires. CFT garantit la livraison de ces fichiers avec chiffrement, acquittement, reprise automatique et traçabilité complète — des exigences réglementaires strictes.

## Architecture CFT dans le projet

```
┌─────────────┐    PeSIT/TLS    ┌──────────────┐
│  Bank-Ops   │ ──────────────► │     BCE      │  Rapports COREP
│  (CFT)      │ ◄────────────── │              │  Données de référence
└─────────────┘                 └──────────────┘

┌─────────────┐    PeSIT/TLS    ┌──────────────┐
│  Bank-Ops   │ ──────────────► │     STET     │  Virements SCT
│  (CFT)      │ ◄────────────── │              │  Prélèvements SDD
└─────────────┘                 └──────────────┘

┌─────────────┐    SFTP/TLS     ┌──────────────┐
│  Bank-Ops   │ ──────────────► │    SWIFT     │  Messages MT103
│  (CFT)      │ ◄────────────── │              │  Relevés MT940
└─────────────┘                 └──────────────┘
```

## Concepts clés

### CFTPART (Partenaire)
Définit un partenaire distant : adresse, port, protocole, chiffrement. Chaque partenaire a un identifiant unique.

### CFTSEND (Flux sortant)
Définit un type de fichier à envoyer vers un partenaire : nom du fichier, format, répertoire source.

### CFTRECV (Flux entrant)
Définit un type de fichier attendu d'un partenaire : nom du fichier, répertoire de destination.

### Protocoles
- **PeSIT** : Protocole historique bancaire français, optimisé pour les gros volumes avec reprise sur point de contrôle.
- **SFTP** : Alternative pour les partenaires internationaux (SWIFT).

## Fichiers de configuration du projet

### partners.cfg

Définit trois partenaires :

| Partenaire | Protocole | Flux sortants | Flux entrants |
|---|---|---|---|
| BCE | PeSIT/TLS | COREP mensuel | Données de référence |
| STET | PeSIT/TLS | SCT, SDD | Acquittements |
| SWIFT | SFTP/TLS | MT103 | MT940 |

### monitor_transfers.sh

Script de supervision qui vérifie le statut du serveur CFT, liste les transferts du jour, attend les fichiers entrants (avec timeout configurable) et vérifie l'intégrité des fichiers reçus (taille, checksum SHA-256).

## Commandes CFT utiles

```bash
# Vérifier le statut du serveur CFT
CFTUTIL ABOUT

# Lister les transferts du jour
CFTUTIL LISTCAT DIRECT=SEND DATEFB=20260314
CFTUTIL LISTCAT DIRECT=RECV DATEFB=20260314

# Envoyer un fichier manuellement
CFTUTIL SEND PART=STET, IDF=SEPA_CREDIT_TRANSFER

# Vérifier un transfert spécifique
CFTUTIL DISPLAY IDTU=A0001234

# Relancer un transfert en échec
CFTUTIL START IDTU=A0001234

# Purger le catalogue (transferts > 30 jours)
CFTUTIL PURGE DATEFB=-30

# Voir les partenaires configurés
CFTUTIL LISTPART
```

## Flux quotidien typique

1. **02:00** — Autosys déclenche le batch
2. **02:05** — CFT reçoit les fichiers des partenaires (STET acquittements, SWIFT MT940, BCE refdata)
3. **02:30** — Les fichiers sont validés et traités par les scripts Shell
4. **04:00** — CFT envoie les fichiers sortants (SCT, SDD, MT103, COREP)
5. **04:30** — `monitor_transfers.sh` vérifie que tous les transferts sont en statut DONE

## Bonnes pratiques

1. Toujours utiliser TLS 1.3 pour les connexions partenaires.
2. Vérifier les checksums SHA-256 à la réception.
3. Configurer des retries automatiques (3 tentatives avec backoff).
4. Archiver les fichiers transférés avec horodatage.
5. Surveiller les transferts en temps réel via Dynatrace.
6. Tester les flux de bout en bout en staging avant la mise en production.
