# Runbook — Procédures d'exploitation Bank-Ops-Lab

## Table des procédures

1. Incident : Batch quotidien en échec
2. Incident : Transfert CFT en erreur
3. Incident : WebSphere ne répond plus
4. Incident : Pod Kubernetes en CrashLoopBackOff
5. Maintenance : Déploiement d'une nouvelle version
6. Maintenance : Rotation des certificats TLS

---

## 1. Batch quotidien en échec

**Symptôme** : Alerte Dynatrace "BANK_DAILY_BOX — FAILURE" ou Autosys `autorep -j BANK_DAILY_BOX` montre un statut FA.

**Diagnostic** :

```bash
# Identifier le job en échec
autorep -j BANK_DAILY_BOX -s

# Consulter les logs du job en échec (exemple : BANK_PROCESS_TX)
cat /var/log/bank-ops/autosys/process_tx.err
cat /var/log/bank-ops/batch_$(date +%Y-%m-%d).log

# Vérifier l'espace disque
df -h /opt/bank-ops/data/

# Vérifier la connectivité base de données
pg_isready -h localhost -p 5432 -U bankops_admin
```

**Résolution** :

```bash
# Si le problème est un fichier manquant ou corrompu :
# 1. Vérifier les transferts CFT
./scripts/cft/monitor_transfers.sh --direction IN

# 2. Re-demander le fichier au partenaire si nécessaire
CFTUTIL SEND PART=STET, IDF=ACK_REPORT

# 3. Relancer le job en échec
sendevent -E FORCE_STARTJOB -J BANK_PROCESS_TX

# Si le problème est applicatif :
# 1. Vérifier les logs applicatifs
tail -100 /var/log/bank-ops/batch_$(date +%Y-%m-%d).log

# 2. Corriger le problème (données, config)
# 3. Relancer le batch complet si nécessaire
sendevent -E FORCE_STARTJOB -J BANK_DAILY_BOX
```

**Escalade** : Si le batch n'est pas terminé avant 07:00, escalader au N2 (responsable exploitation).

---

## 2. Transfert CFT en erreur

**Symptôme** : Alerte Dynatrace "CFT Transfer Failed" ou `monitor_transfers.sh` retourne des erreurs.

**Diagnostic** :

```bash
# Lister les transferts en erreur
CFTUTIL LISTCAT STATE=DISP DIRECT=SEND
CFTUTIL LISTCAT STATE=DISP DIRECT=RECV

# Voir le détail d'un transfert
CFTUTIL DISPLAY IDTU=<ID_TRANSFERT>

# Vérifier la connectivité réseau vers le partenaire
telnet cft.stet.eu 1762
openssl s_client -connect cft.stet.eu:1762 -tls1_3

# Vérifier les certificats
openssl x509 -in /opt/cft/certs/bankops.pem -noout -dates
```

**Résolution** :

```bash
# Relancer le transfert
CFTUTIL START IDTU=<ID_TRANSFERT>

# Si le partenaire est injoignable, attendre et retenter
CFTUTIL RETRY IDTU=<ID_TRANSFERT>

# Si le certificat est expiré → procédure 6 (rotation certificats)
```

**Escalade** : Si le transfert concerne un flux réglementaire (COREP, SWIFT), escalader immédiatement au responsable conformité.

---

## 3. WebSphere ne répond plus

**Symptôme** : HTTP 502/503 sur les endpoints `/app/*`, Dynatrace signale "Service unavailable".

**Diagnostic** :

```bash
# Vérifier le statut du service
systemctl status wlp

# Vérifier les logs Liberty
tail -200 /opt/ibm/wlp/output/defaultServer/logs/messages.log

# Vérifier la mémoire JVM
jcmd $(pgrep -f wlp) GC.heap_info

# Vérifier les connexions JDBC
curl -s http://localhost:9080/metrics | grep jdbc

# Vérifier l'espace disque (les logs peuvent remplir le disque)
df -h /opt/ibm/wlp/output/
```

**Résolution** :

```bash
# Redémarrer le service
systemctl restart wlp

# Attendre que le health check passe
watch -n5 'curl -s http://localhost:9080/health'

# Si OutOfMemoryError dans les logs → augmenter le heap
# Modifier JVM_ARGS dans server.xml : -Xmx768m → -Xmx1024m
# Puis redémarrer

# Si pool JDBC saturé → vérifier les connexions PostgreSQL
psql -h localhost -U bankops_admin -c "SELECT count(*) FROM pg_stat_activity;"
```

**Escalade** : Si le redémarrage ne résout pas le problème, escalader au développeur Java de l'équipe.

---

## 4. Pod Kubernetes en CrashLoopBackOff

**Symptôme** : `kubectl get pods -n bankops` montre un pod en CrashLoopBackOff.

**Diagnostic** :

```bash
# Identifier le pod problématique
kubectl get pods -n bankops -o wide

# Voir les événements
kubectl describe pod <POD_NAME> -n bankops

# Consulter les logs du conteneur
kubectl logs <POD_NAME> -n bankops --previous
kubectl logs <POD_NAME> -n bankops -f

# Vérifier les ressources du nœud
kubectl top nodes
kubectl top pods -n bankops

# Vérifier les secrets et configmaps
kubectl get secret bankops-secrets -n bankops -o yaml
kubectl get configmap bankops-config -n bankops -o yaml
```

**Résolution** :

```bash
# Si OOMKilled → augmenter les limits mémoire
kubectl edit deployment <DEPLOYMENT_NAME> -n bankops
# resources.limits.memory: 512Mi → 768Mi

# Si erreur de configuration → corriger le configmap
kubectl edit configmap bankops-config -n bankops

# Si image corrompue → forcer un re-pull
kubectl rollout restart deployment/<DEPLOYMENT_NAME> -n bankops

# Si le problème persiste → rollback
kubectl rollout undo deployment/<DEPLOYMENT_NAME> -n bankops
kubectl rollout status deployment/<DEPLOYMENT_NAME> -n bankops
```

**Escalade** : Si le rollback échoue, contacter l'administrateur Kubernetes.

---

## 5. Déploiement d'une nouvelle version

**Pré-requis** : Version testée et validée en staging.

```bash
# 1. Vérifier l'état actuel
./scripts/shell/health_check.sh --json

# 2. Prévenir l'équipe
# → Message Slack #ops-deploys

# 3. Déployer via Ansible (WebSphere bare-metal)
cd ansible/
ansible-playbook -i inventory/production.ini playbooks/deploy_app.yml \
    -e "version=1.2.3" --check  # Dry-run d'abord
ansible-playbook -i inventory/production.ini playbooks/deploy_app.yml \
    -e "version=1.2.3"

# 4. Déployer sur Kubernetes
ansible-playbook -i inventory/production.ini playbooks/rolling_update.yml \
    -e "image_tag=1.2.3"

# 5. Vérification post-déploiement
./scripts/shell/health_check.sh --json
kubectl get pods -n bankops
curl -s http://localhost:8080/actuator/info | jq '.build.version'

# 6. Surveiller Dynatrace pendant 30 minutes
# → Dashboard Bank-Ops : taux d'erreur, temps de réponse

# 7. Si problème → rollback
kubectl rollout undo deployment/bankops-api -n bankops
```

---

## 6. Rotation des certificats TLS

**Fréquence** : Annuelle ou en cas d'alerte d'expiration (30 jours avant).

```bash
# 1. Vérifier la date d'expiration actuelle
openssl x509 -in /opt/cft/certs/bankops.pem -noout -enddate
openssl x509 -in /opt/ibm/wlp/usr/servers/defaultServer/resources/security/key.p12 -noout -enddate

# 2. Générer un nouveau certificat (ou recevoir du PKI interne)
openssl req -new -x509 -days 365 -nodes \
    -keyout /tmp/new_key.pem \
    -out /tmp/new_cert.pem \
    -subj "/CN=bankops.internal.prod/O=BankOps/C=FR"

# 3. Déployer via Ansible
ansible-playbook -i inventory/production.ini playbooks/rotate_certs.yml \
    -e "cert_file=/tmp/new_cert.pem key_file=/tmp/new_key.pem"

# 4. Redémarrer les services concernés
systemctl restart wlp
systemctl restart cft
kubectl rollout restart deployment -n bankops

# 5. Vérifier la connectivité
openssl s_client -connect localhost:9443 -tls1_3
./scripts/cft/monitor_transfers.sh --direction OUT
```

---

## Contacts d'escalade

| Niveau | Rôle | Disponibilité |
|---|---|---|
| N1 | Opérateur de production | 24/7 |
| N2 | Ingénieur Ops senior | Jours ouvrés 8h-20h |
| N3 | Architecte / Dev lead | Sur appel |
| Conformité | Responsable réglementaire | Jours ouvrés |
