#!/bin/bash
###############################################################################
# monitor_transfers.sh — Supervision des transferts CFT
# Usage : ./monitor_transfers.sh --direction [IN|OUT] [--wait SECONDS]
###############################################################################
set -euo pipefail

CFT_HOME="/opt/cft"
LOG_DIR="/var/log/bank-ops/cft"
DIRECTION="IN"
WAIT_TIMEOUT=0
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TODAY=$(date '+%Y%m%d')

while [[ $# -gt 0 ]]; do
    case $1 in
        --direction|-d) DIRECTION="$2"; shift 2 ;;
        --wait|-w)      WAIT_TIMEOUT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CFT] [$1] $2"; }

mkdir -p "${LOG_DIR}"

# ─── Vérifier le statut du serveur CFT ───────────────────────────────────
check_cft_status() {
    log "INFO" "Vérification du serveur CFT..."

    # Simuler la commande CFTUTIL (en production : CFTUTIL /m=2 ABOUT)
    if command -v CFTUTIL &>/dev/null; then
        local status
        status=$(CFTUTIL ABOUT 2>/dev/null | grep "State" | awk '{print $3}')
        if [[ "${status}" == "ACTIVE" ]]; then
            log "INFO" "Serveur CFT: ACTIF"
            return 0
        else
            log "ERROR" "Serveur CFT: ${status:-INCONNU}"
            return 1
        fi
    else
        log "WARN" "CFTUTIL non disponible — mode simulation"
        return 0
    fi
}

# ─── Lister les transferts du jour ───────────────────────────────────────
list_transfers() {
    local direction="$1"
    log "INFO" "Liste des transferts ${direction} du ${TODAY}"

    # En production : CFTUTIL LISTCAT DIRECT=${direction} DATEFB=${TODAY}
    # Simulation avec fichiers locaux
    local data_dir
    if [[ "${direction}" == "IN" ]]; then
        data_dir="/opt/bank-ops/data/incoming"
    else
        data_dir="/opt/bank-ops/data/outgoing"
    fi

    if [[ -d "${data_dir}" ]]; then
        local count
        count=$(find "${data_dir}" -name "*${TODAY}*" -type f 2>/dev/null | wc -l)
        log "INFO" "  ${count} fichier(s) trouvé(s)"

        find "${data_dir}" -name "*${TODAY}*" -type f -printf "  → %f (%s octets, %Tc)\n" 2>/dev/null || true
    else
        log "WARN" "Répertoire ${data_dir} inexistant"
    fi
}

# ─── Attendre les fichiers entrants ──────────────────────────────────────
wait_for_files() {
    local timeout="$1"
    local watch_dir="/opt/bank-ops/data/incoming"
    local start_time
    start_time=$(date +%s)

    log "INFO" "Attente de fichiers entrants (timeout: ${timeout}s)..."

    while true; do
        local elapsed=$(( $(date +%s) - start_time ))

        if [[ ${elapsed} -ge ${timeout} ]]; then
            log "WARN" "Timeout atteint (${timeout}s) — aucun nouveau fichier"
            return 1
        fi

        local new_files
        new_files=$(find "${watch_dir}" -name "*${TODAY}*" -newer "/tmp/.cft_last_check" -type f 2>/dev/null | wc -l)

        if [[ ${new_files} -gt 0 ]]; then
            log "INFO" "${new_files} nouveau(x) fichier(s) détecté(s)"
            touch "/tmp/.cft_last_check"
            return 0
        fi

        sleep 30
        log "INFO" "  En attente... (${elapsed}/${timeout}s)"
    done
}

# ─── Vérifier l'intégrité des transferts ─────────────────────────────────
verify_integrity() {
    local direction="$1"
    local data_dir

    if [[ "${direction}" == "IN" ]]; then
        data_dir="/opt/bank-ops/data/incoming"
    else
        data_dir="/opt/bank-ops/data/outgoing"
    fi

    log "INFO" "Vérification d'intégrité des fichiers ${direction}..."

    local error_count=0
    while IFS= read -r -d '' file; do
        local filename
        filename=$(basename "${file}")

        # Vérifier que le fichier n'est pas vide
        if [[ ! -s "${file}" ]]; then
            log "ERROR" "  ${filename}: VIDE"
            ((error_count++))
            continue
        fi

        # Vérifier le checksum si disponible
        if [[ -f "${file}.sha256" ]]; then
            if sha256sum -c "${file}.sha256" &>/dev/null; then
                log "INFO" "  ${filename}: OK (checksum vérifié)"
            else
                log "ERROR" "  ${filename}: CHECKSUM INVALIDE"
                ((error_count++))
            fi
        else
            local size
            size=$(stat -f%z "${file}" 2>/dev/null || stat -c%s "${file}" 2>/dev/null || echo "?")
            log "INFO" "  ${filename}: OK (${size} octets, pas de checksum)"
        fi
    done < <(find "${data_dir}" -name "*${TODAY}*" -type f -print0 2>/dev/null)

    if [[ ${error_count} -gt 0 ]]; then
        log "ERROR" "${error_count} erreur(s) d'intégrité détectée(s)"
        return 1
    fi

    log "INFO" "Intégrité vérifiée — aucune anomalie"
    return 0
}

# ─── Exécution principale ────────────────────────────────────────────────
log "INFO" "══════════════════════════════════════"
log "INFO" "Supervision CFT — Direction: ${DIRECTION}"
log "INFO" "══════════════════════════════════════"

check_cft_status

if [[ "${DIRECTION}" == "IN" && ${WAIT_TIMEOUT} -gt 0 ]]; then
    touch "/tmp/.cft_last_check"
    wait_for_files "${WAIT_TIMEOUT}"
fi

list_transfers "${DIRECTION}"
verify_integrity "${DIRECTION}"

log "INFO" "Supervision terminée"
