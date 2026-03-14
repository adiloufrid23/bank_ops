#!/bin/bash
###############################################################################
# log_rotate.sh — Rotation, compression et purge des logs applicatifs
# Usage : ./log_rotate.sh [--retention-days 30] [--compress]
###############################################################################
set -euo pipefail

LOG_BASE_DIR="/var/log/bank-ops"
RETENTION_DAYS=30
COMPRESS=true
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

while [[ $# -gt 0 ]]; do
    case $1 in
        --retention-days) RETENTION_DAYS="$2"; shift 2 ;;
        --no-compress)    COMPRESS=false; shift ;;
        *) shift ;;
    esac
done

echo "[${TIMESTAMP}] Début rotation des logs (rétention: ${RETENTION_DAYS}j)"

# Compresser les logs de plus de 1 jour
if [[ "${COMPRESS}" == true ]]; then
    find "${LOG_BASE_DIR}" -name "*.log" -mtime +1 -not -name "*.gz" -exec gzip -9 {} \;
    compressed=$(find "${LOG_BASE_DIR}" -name "*.log.gz" -mtime -1 | wc -l)
    echo "[${TIMESTAMP}] ${compressed} fichier(s) compressé(s)"
fi

# Purger les logs au-delà de la rétention
purged=$(find "${LOG_BASE_DIR}" -name "*.log.gz" -mtime +${RETENTION_DAYS} -delete -print | wc -l)
echo "[${TIMESTAMP}] ${purged} fichier(s) purgé(s) (> ${RETENTION_DAYS}j)"

# Vérifier l'espace disque libéré
disk_usage=$(du -sh "${LOG_BASE_DIR}" 2>/dev/null | awk '{print $1}')
echo "[${TIMESTAMP}] Espace total logs: ${disk_usage}"
echo "[${TIMESTAMP}] Rotation terminée"
