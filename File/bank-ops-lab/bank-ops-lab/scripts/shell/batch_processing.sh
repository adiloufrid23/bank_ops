#!/bin/bash
###############################################################################
# batch_processing.sh — Traitement batch des transactions bancaires
# Usage : ./batch_processing.sh --date YYYY-MM-DD [--dry-run]
# Description : Parse les fichiers de transactions, valide, calcule les soldes,
#               génère les rapports de réconciliation
###############################################################################
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
SCRIPT_NAME="$(basename "$0")"
BASE_DIR="/opt/bank-ops"
INPUT_DIR="${BASE_DIR}/data/incoming"
OUTPUT_DIR="${BASE_DIR}/data/processed"
ARCHIVE_DIR="${BASE_DIR}/data/archive"
REPORT_DIR="${BASE_DIR}/reports"
LOG_DIR="/var/log/bank-ops"
LOCK_FILE="/tmp/${SCRIPT_NAME}.lock"

BATCH_DATE=""
DRY_RUN=false
TOTAL_TRANSACTIONS=0
TOTAL_AMOUNT=0
ERROR_COUNT=0
PROCESSED_COUNT=0

# ─── Parsing arguments ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --date|-d)    BATCH_DATE="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: $0 --date YYYY-MM-DD [--dry-run]"
            echo "  --date     Date du batch à traiter"
            echo "  --dry-run  Exécution simulée (aucune écriture)"
            exit 0
            ;;
        *) echo "Option inconnue: $1"; exit 1 ;;
    esac
done

if [[ -z "${BATCH_DATE}" ]]; then
    echo "ERREUR: --date est obligatoire"
    exit 1
fi

# Valider le format de date
if ! date -d "${BATCH_DATE}" +%Y-%m-%d &>/dev/null; then
    echo "ERREUR: Format de date invalide. Utiliser YYYY-MM-DD"
    exit 1
fi

LOG_FILE="${LOG_DIR}/batch_${BATCH_DATE}.log"

# ─── Fonctions utilitaires ──────────────────────────────────────────────────
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] [${SCRIPT_NAME}] ${message}" | tee -a "${LOG_FILE}"
}

cleanup() {
    rm -f "${LOCK_FILE}"
    log "INFO" "Lock file supprimé"
}

trap cleanup EXIT

acquire_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        local pid
        pid=$(cat "${LOCK_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            log "ERROR" "Un batch est déjà en cours (PID: ${pid})"
            exit 1
        else
            log "WARN" "Lock file orphelin trouvé, nettoyage..."
            rm -f "${LOCK_FILE}"
        fi
    fi
    echo $$ > "${LOCK_FILE}"
    log "INFO" "Lock acquis (PID: $$)"
}

validate_transaction() {
    local line="$1"
    local line_num="$2"

    # Format attendu : ID;DATE;DEBITEUR;CREDITEUR;MONTANT;DEVISE;TYPE
    local field_count
    field_count=$(echo "${line}" | awk -F';' '{print NF}')

    if [[ ${field_count} -ne 7 ]]; then
        log "WARN" "Ligne ${line_num}: Nombre de champs incorrect (${field_count}/7)"
        return 1
    fi

    local tx_id tx_date debiteur crediteur montant devise tx_type
    IFS=';' read -r tx_id tx_date debiteur crediteur montant devise tx_type <<< "${line}"

    # Vérifier que le montant est numérique et positif
    if ! [[ "${montant}" =~ ^[0-9]+(\.[0-9]{1,2})?$ ]]; then
        log "WARN" "Ligne ${line_num}: Montant invalide '${montant}' (TX: ${tx_id})"
        return 1
    fi

    # Vérifier la devise
    if [[ "${devise}" != "EUR" && "${devise}" != "USD" && "${devise}" != "GBP" ]]; then
        log "WARN" "Ligne ${line_num}: Devise non supportée '${devise}' (TX: ${tx_id})"
        return 1
    fi

    # Vérifier le type de transaction
    if [[ "${tx_type}" != "VIREMENT" && "${tx_type}" != "PRELEVEMENT" && "${tx_type}" != "CARTE" ]]; then
        log "WARN" "Ligne ${line_num}: Type non reconnu '${tx_type}' (TX: ${tx_id})"
        return 1
    fi

    return 0
}

process_file() {
    local input_file="$1"
    local filename
    filename=$(basename "${input_file}")
    local output_file="${OUTPUT_DIR}/${filename%.csv}_processed.csv"
    local error_file="${OUTPUT_DIR}/${filename%.csv}_errors.csv"

    log "INFO" "Traitement du fichier: ${filename}"

    local line_num=0
    local file_amount=0
    local file_tx_count=0
    local file_error_count=0

    # Écrire les en-têtes
    if [[ "${DRY_RUN}" == false ]]; then
        echo "TX_ID;DATE;DEBITEUR;CREDITEUR;MONTANT;DEVISE;TYPE;STATUT;TIMESTAMP" > "${output_file}"
        echo "LIGNE;ERREUR;CONTENU" > "${error_file}"
    fi

    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_num++))

        # Ignorer l'en-tête
        [[ ${line_num} -eq 1 ]] && continue

        # Ignorer les lignes vides
        [[ -z "${line}" ]] && continue

        ((TOTAL_TRANSACTIONS++))
        ((file_tx_count++))

        if validate_transaction "${line}" "${line_num}"; then
            local montant
            montant=$(echo "${line}" | awk -F';' '{print $5}')
            file_amount=$(echo "${file_amount} + ${montant}" | bc)

            if [[ "${DRY_RUN}" == false ]]; then
                echo "${line};VALIDE;$(date -Iseconds)" >> "${output_file}"
            fi
            ((PROCESSED_COUNT++))
        else
            if [[ "${DRY_RUN}" == false ]]; then
                echo "${line_num};VALIDATION_FAILED;${line}" >> "${error_file}"
            fi
            ((ERROR_COUNT++))
            ((file_error_count++))
        fi
    done < "${input_file}"

    TOTAL_AMOUNT=$(echo "${TOTAL_AMOUNT} + ${file_amount}" | bc)

    log "INFO" "  → ${file_tx_count} transactions, ${file_error_count} erreurs, montant: ${file_amount} EUR"

    # Archiver le fichier source
    if [[ "${DRY_RUN}" == false ]]; then
        local archive_path="${ARCHIVE_DIR}/$(date -d "${BATCH_DATE}" +%Y/%m)"
        mkdir -p "${archive_path}"
        cp "${input_file}" "${archive_path}/${filename}.$(date +%H%M%S)"
        log "INFO" "  → Archivé dans ${archive_path}"
    fi
}

generate_report() {
    local report_file="${REPORT_DIR}/reconciliation_${BATCH_DATE}.txt"

    log "INFO" "Génération du rapport de réconciliation"

    if [[ "${DRY_RUN}" == true ]]; then
        log "INFO" "[DRY-RUN] Rapport non généré"
        return
    fi

    mkdir -p "${REPORT_DIR}"

    cat > "${report_file}" <<EOF
═══════════════════════════════════════════════════════════════
  RAPPORT DE RÉCONCILIATION — BATCH DU ${BATCH_DATE}
  Généré le : $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════════════════════

  Transactions totales    : ${TOTAL_TRANSACTIONS}
  Transactions traitées   : ${PROCESSED_COUNT}
  Transactions en erreur  : ${ERROR_COUNT}
  Taux de succès          : $(echo "scale=2; ${PROCESSED_COUNT} * 100 / ${TOTAL_TRANSACTIONS}" | bc 2>/dev/null || echo "N/A")%

  Montant total traité    : ${TOTAL_AMOUNT} EUR

═══════════════════════════════════════════════════════════════
  STATUT : $([ ${ERROR_COUNT} -eq 0 ] && echo "OK — Aucune anomalie" || echo "ALERTE — ${ERROR_COUNT} anomalies détectées")
═══════════════════════════════════════════════════════════════
EOF

    log "INFO" "Rapport généré: ${report_file}"
}

# ─── Exécution principale ────────────────────────────────────────────────────
log "INFO" "============================================"
log "INFO" "Début du batch — Date: ${BATCH_DATE}"
[[ "${DRY_RUN}" == true ]] && log "INFO" "Mode DRY-RUN activé"
log "INFO" "============================================"

acquire_lock

# Créer les répertoires si nécessaire
for dir in "${INPUT_DIR}" "${OUTPUT_DIR}" "${ARCHIVE_DIR}" "${REPORT_DIR}" "${LOG_DIR}"; do
    mkdir -p "${dir}" 2>/dev/null || true
done

# Rechercher les fichiers à traiter
input_files=("${INPUT_DIR}"/transactions_${BATCH_DATE}*.csv)

if [[ ! -f "${input_files[0]:-}" ]]; then
    log "WARN" "Aucun fichier trouvé pour la date ${BATCH_DATE}"
    log "INFO" "Recherche dans: ${INPUT_DIR}/transactions_${BATCH_DATE}*.csv"
    exit 0
fi

log "INFO" "${#input_files[@]} fichier(s) à traiter"

# Traiter chaque fichier
for file in "${input_files[@]}"; do
    process_file "${file}"
done

# Générer le rapport
generate_report

# Résumé
log "INFO" "============================================"
log "INFO" "Batch terminé"
log "INFO" "  Total TX    : ${TOTAL_TRANSACTIONS}"
log "INFO" "  Traitées    : ${PROCESSED_COUNT}"
log "INFO" "  Erreurs     : ${ERROR_COUNT}"
log "INFO" "  Montant     : ${TOTAL_AMOUNT} EUR"
log "INFO" "============================================"

exit ${GLOBAL_STATUS:-0}
