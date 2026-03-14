#!/bin/bash
###############################################################################
# health_check.sh — Vérification de la santé de l'ensemble des services
# Usage : ./health_check.sh [--verbose] [--json]
# Retour : 0 si tous les services sont OK, 1 sinon
###############################################################################
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/bank-ops"
LOG_FILE="${LOG_DIR}/health_check_$(date +%Y%m%d).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Services à vérifier (nom:url:port)
declare -A SERVICES=(
    ["websphere"]="http://localhost:9080/health"
    ["api-rest"]="http://localhost:8080/actuator/health"
    ["nginx"]="http://localhost:80/nginx-health"
    ["database"]="localhost:5432"
)

VERBOSE=false
JSON_OUTPUT=false
GLOBAL_STATUS=0

# ─── Parsing arguments ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v) VERBOSE=true; shift ;;
        --json|-j)    JSON_OUTPUT=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--verbose] [--json]"
            echo "  --verbose  Affiche les détails de chaque vérification"
            echo "  --json     Sortie au format JSON"
            exit 0
            ;;
        *) echo "Option inconnue: $1"; exit 1 ;;
    esac
done

# ─── Fonctions utilitaires ──────────────────────────────────────────────────
log() {
    local level="$1"
    local message="$2"
    echo "[${TIMESTAMP}] [${level}] ${message}" | tee -a "${LOG_FILE}" 2>/dev/null || true
}

check_http_service() {
    local name="$1"
    local url="$2"
    local timeout=5

    if response=$(curl -s -o /dev/null -w "%{http_code}" --max-time ${timeout} "${url}" 2>/dev/null); then
        if [[ "${response}" == "200" ]]; then
            log "INFO" "${name}: UP (HTTP ${response})"
            echo "UP"
            return 0
        else
            log "WARN" "${name}: DEGRADED (HTTP ${response})"
            echo "DEGRADED"
            return 1
        fi
    else
        log "ERROR" "${name}: DOWN (timeout après ${timeout}s)"
        echo "DOWN"
        return 1
    fi
}

check_tcp_port() {
    local name="$1"
    local host_port="$2"
    local host="${host_port%%:*}"
    local port="${host_port##*:}"
    local timeout=3

    if timeout ${timeout} bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null; then
        log "INFO" "${name}: UP (port ${port} ouvert)"
        echo "UP"
        return 0
    else
        log "ERROR" "${name}: DOWN (port ${port} fermé)"
        echo "DOWN"
        return 1
    fi
}

check_disk_space() {
    local threshold=90
    local usage
    usage=$(df -h / | awk 'NR==2 {gsub(/%/,""); print $5}')

    if [[ ${usage} -lt ${threshold} ]]; then
        log "INFO" "Disque: OK (${usage}% utilisé)"
        echo "OK:${usage}%"
        return 0
    else
        log "WARN" "Disque: ALERTE (${usage}% utilisé, seuil: ${threshold}%)"
        echo "ALERT:${usage}%"
        return 1
    fi
}

check_memory() {
    local threshold=90
    local usage
    usage=$(free | awk '/Mem:/ {printf("%.0f", $3/$2 * 100)}')

    if [[ ${usage} -lt ${threshold} ]]; then
        log "INFO" "Mémoire: OK (${usage}% utilisée)"
        echo "OK:${usage}%"
        return 0
    else
        log "WARN" "Mémoire: ALERTE (${usage}% utilisée, seuil: ${threshold}%)"
        echo "ALERT:${usage}%"
        return 1
    fi
}

check_load_average() {
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || echo 1)
    local load_1min
    load_1min=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0")
    local threshold
    threshold=$(echo "${cpu_count} * 2" | bc 2>/dev/null || echo "4")

    if (( $(echo "${load_1min} < ${threshold}" | bc -l 2>/dev/null || echo 1) )); then
        log "INFO" "Load: OK (${load_1min}, seuil: ${threshold})"
        echo "OK:${load_1min}"
        return 0
    else
        log "WARN" "Load: ALERTE (${load_1min}, seuil: ${threshold})"
        echo "ALERT:${load_1min}"
        return 1
    fi
}

# ─── Exécution des checks ───────────────────────────────────────────────────
declare -A RESULTS=()

log "INFO" "====== Début du health check ======"

# Check services applicatifs
for service in "${!SERVICES[@]}"; do
    url="${SERVICES[${service}]}"

    if [[ "${url}" =~ ^http ]]; then
        result=$(check_http_service "${service}" "${url}") || true
    else
        result=$(check_tcp_port "${service}" "${url}") || true
    fi

    RESULTS["${service}"]="${result}"
    if [[ "${result}" != "UP" ]]; then
        GLOBAL_STATUS=1
    fi
done

# Check système
disk_result=$(check_disk_space) || GLOBAL_STATUS=1
RESULTS["disk"]="${disk_result}"

mem_result=$(check_memory) || GLOBAL_STATUS=1
RESULTS["memory"]="${mem_result}"

load_result=$(check_load_average) || GLOBAL_STATUS=1
RESULTS["load"]="${load_result}"

# ─── Affichage des résultats ─────────────────────────────────────────────────
if [[ "${JSON_OUTPUT}" == true ]]; then
    echo "{"
    echo "  \"timestamp\": \"${TIMESTAMP}\","
    echo "  \"global_status\": \"$([ ${GLOBAL_STATUS} -eq 0 ] && echo 'HEALTHY' || echo 'UNHEALTHY')\","
    echo "  \"checks\": {"
    first=true
    for key in "${!RESULTS[@]}"; do
        [[ "${first}" == true ]] && first=false || echo ","
        printf '    "%s": "%s"' "${key}" "${RESULTS[${key}]}"
    done
    echo ""
    echo "  }"
    echo "}"
else
    echo "═══════════════════════════════════════════"
    echo "  HEALTH CHECK — ${TIMESTAMP}"
    echo "═══════════════════════════════════════════"
    for key in "${!RESULTS[@]}"; do
        status="${RESULTS[${key}]}"
        icon="✅"
        [[ "${status}" == "DOWN" ]] && icon="❌"
        [[ "${status}" == "DEGRADED" ]] && icon="⚠️"
        [[ "${status}" =~ ^ALERT ]] && icon="⚠️"
        printf "  %s  %-15s %s\n" "${icon}" "${key}" "${status}"
    done
    echo "═══════════════════════════════════════════"
    if [[ ${GLOBAL_STATUS} -eq 0 ]]; then
        echo "  ✅ STATUT GLOBAL : HEALTHY"
    else
        echo "  ❌ STATUT GLOBAL : UNHEALTHY"
    fi
    echo "═══════════════════════════════════════════"
fi

log "INFO" "====== Fin du health check (status: ${GLOBAL_STATUS}) ======"
exit ${GLOBAL_STATUS}
