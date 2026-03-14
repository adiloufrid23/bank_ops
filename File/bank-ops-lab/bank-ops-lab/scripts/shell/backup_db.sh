#!/bin/bash
###############################################################################
# backup_db.sh — Sauvegarde base de données PostgreSQL avec chiffrement
# Usage : ./backup_db.sh [--full|--incremental] [--encrypt]
###############################################################################
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
BACKUP_DIR="/opt/bank-ops/backups"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-bankops}"
DB_USER="${DB_USER:-bankops_admin}"
BACKUP_TYPE="full"
ENCRYPT=false
RETENTION_DAYS=7
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)         BACKUP_TYPE="full"; shift ;;
        --incremental)  BACKUP_TYPE="incremental"; shift ;;
        --encrypt)      ENCRYPT=true; shift ;;
        *) shift ;;
    esac
done

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] [${SCRIPT_NAME}] $2"; }

log "INFO" "Début sauvegarde ${BACKUP_TYPE} de ${DB_NAME}"

mkdir -p "${BACKUP_DIR}/${BACKUP_TYPE}"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_TYPE}/${DB_NAME}_${BACKUP_TYPE}_${TIMESTAMP}.sql.gz"

# Dump et compression
log "INFO" "Dump en cours..."
pg_dump -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -Fc "${DB_NAME}" 2>/dev/null | \
    gzip -9 > "${BACKUP_FILE}"

BACKUP_SIZE=$(du -sh "${BACKUP_FILE}" | awk '{print $1}')
log "INFO" "Dump terminé: ${BACKUP_FILE} (${BACKUP_SIZE})"

# Chiffrement optionnel
if [[ "${ENCRYPT}" == true ]]; then
    log "INFO" "Chiffrement AES-256..."
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "${BACKUP_FILE}" \
        -out "${BACKUP_FILE}.enc" \
        -pass env:BACKUP_PASSPHRASE
    rm -f "${BACKUP_FILE}"
    BACKUP_FILE="${BACKUP_FILE}.enc"
    log "INFO" "Backup chiffré: ${BACKUP_FILE}"
fi

# Vérification d'intégrité
CHECKSUM=$(sha256sum "${BACKUP_FILE}" | awk '{print $1}')
echo "${CHECKSUM}  ${BACKUP_FILE}" > "${BACKUP_FILE}.sha256"
log "INFO" "Checksum SHA-256: ${CHECKSUM:0:16}..."

# Purge des anciens backups
purged=$(find "${BACKUP_DIR}/${BACKUP_TYPE}" -mtime +${RETENTION_DAYS} -delete -print 2>/dev/null | wc -l)
[[ ${purged} -gt 0 ]] && log "INFO" "${purged} anciens backups purgés"

log "INFO" "Sauvegarde terminée avec succès"
