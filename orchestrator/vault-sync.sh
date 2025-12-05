#!/usr/bin/env bash
#
# vault-sync.sh - Idempotent Vault Secret Synchronization Orchestrator
# 
# Features:
# - First-run detection with persistent flag
# - Scroll marking for forced initial ingest
# - Atomic commit ceremonies with all artifacts
# - Checksum verification and automatic rollback
# - Comprehensive audit logging
#
# Usage: ./orchestrator/vault-sync.sh
#

set -euo pipefail

# Configuration
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${ROOT_DIR}/orchestrator/state"
FIRST_RUN_FLAG="${STATE_DIR}/firstrun.flag"
MANIFEST_FILE="${ROOT_DIR}/manifest.json"
CEREMONY_LOG="${ROOT_DIR}/logs/ceremony-$(date -u +%Y%m%d-%H%M%S).log"
AUDIT_LOG="${ROOT_DIR}/logs/audit.log"

# Ensure directories exist
mkdir -p "${STATE_DIR}" "${ROOT_DIR}/envs" "${ROOT_DIR}/metadata" \
         "${ROOT_DIR}/inventories" "${ROOT_DIR}/logs"

# Logging functions
log_ceremony() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "${CEREMONY_LOG}"
}

log_audit() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "${AUDIT_LOG}"
}

log_error() {
    echo "[ERROR] $*" >&2
    log_ceremony "ERROR: $*"
    log_audit "ERROR: $*"
}

# Check if this is first run
is_first_run() {
    [[ ! -f "${FIRST_RUN_FLAG}" ]]
}

# Mark first run as complete
mark_first_run_complete() {
    touch "${FIRST_RUN_FLAG}"
    log_ceremony "First-run flag created: ${FIRST_RUN_FLAG}"
}

# Retrieve secrets from Vault
retrieve_secrets() {
    local is_first=$1
    log_ceremony "Starting secret retrieval (first_run=${is_first})"
    
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        log_error "VAULT_ADDR environment variable not set"
        return 1
    fi
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_error "VAULT_TOKEN environment variable not set"
        return 1
    fi
    
    # Parse space-separated secret paths
    local paths=(${VAULT_SECRET_PATHS:-})
    if [[ ${#paths[@]} -eq 0 ]]; then
        log_error "No secret paths specified in VAULT_SECRET_PATHS"
        return 1
    fi
    
    local retrieved_count=0
    for path in "${paths[@]}"; do
        log_ceremony "Retrieving secret from: ${path}"
        
        # Fetch secret from Vault
        if vault kv get -format=json "${path}" > "/tmp/secret-${retrieved_count}.json" 2>/dev/null; then
            # Extract data and write to envs/
            local secret_name=$(basename "${path}")
            jq -r '.data.data | to_entries[] | "\(.key)=\(.value)"' "/tmp/secret-${retrieved_count}.json" \
                > "${ROOT_DIR}/envs/${secret_name}.env"
            
            # Create metadata with scroll mark if first run
            local metadata_file="${ROOT_DIR}/metadata/${secret_name}.json"
            if [[ "${is_first}" == "true" ]]; then
                jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                      '{scroll: true, retrieved: $ts, version: 1}' \
                      > "${metadata_file}"
                log_ceremony "Marked ${secret_name} as scroll for forced ingest"
            else
                jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                      '{scroll: false, retrieved: $ts, version: 1}' \
                      > "${metadata_file}"
            fi
            
            retrieved_count=$((retrieved_count + 1))
            rm -f "/tmp/secret-${retrieved_count}.json"
        else
            log_error "Failed to retrieve secret: ${path}"
        fi
    done
    
    log_ceremony "Retrieved ${retrieved_count} secrets from Vault"
    return 0
}

# Generate manifest with checksums
generate_manifest() {
    log_ceremony "Generating manifest with checksums"
    
    local manifest_data="{}"
    manifest_data=$(jq -n '{timestamp: $ts, secrets: []}' \
                         --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    
    for env_file in "${ROOT_DIR}"/envs/*.env; do
        if [[ -f "${env_file}" ]]; then
            local name=$(basename "${env_file}" .env)
            local checksum=$(sha256sum "${env_file}" | awk '{print $1}')
            
            manifest_data=$(echo "${manifest_data}" | \
                jq --arg n "${name}" --arg c "${checksum}" \
                   '.secrets += [{name: $n, checksum: $c}]')
        fi
    done
    
    echo "${manifest_data}" | jq . > "${MANIFEST_FILE}"
    log_ceremony "Manifest generated: ${MANIFEST_FILE}"
}

# Verify manifest integrity
verify_manifest() {
    log_ceremony "Verifying manifest integrity"
    
    if [[ ! -f "${MANIFEST_FILE}" ]]; then
        log_error "Manifest file not found: ${MANIFEST_FILE}"
        return 1
    fi
    
    local verification_failed=false
    
    while IFS= read -r secret; do
        local name=$(echo "${secret}" | jq -r '.name')
        local expected_checksum=$(echo "${secret}" | jq -r '.checksum')
        local env_file="${ROOT_DIR}/envs/${name}.env"
        
        if [[ -f "${env_file}" ]]; then
            local actual_checksum=$(sha256sum "${env_file}" | awk '{print $1}')
            
            if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
                log_error "Checksum mismatch for ${name}: expected ${expected_checksum}, got ${actual_checksum}"
                verification_failed=true
            else
                log_ceremony "Checksum verified for ${name}"
            fi
        else
            log_error "Expected file not found: ${env_file}"
            verification_failed=true
        fi
    done < <(jq -c '.secrets[]' "${MANIFEST_FILE}")
    
    if [[ "${verification_failed}" == "true" ]]; then
        log_error "Manifest verification FAILED"
        return 1
    fi
    
    log_ceremony "Manifest verification PASSED"
    return 0
}

# Perform atomic commit ceremony
commit_ceremony() {
    log_ceremony "Starting atomic commit ceremony"
    
    # Stage all ceremony artifacts
    git add envs/ metadata/ inventories/ manifest.json logs/
    
    # Create commit with ceremony timestamp
    local commit_msg="[Ceremony] Vault sync - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if git commit -m "${commit_msg}"; then
        log_ceremony "Ceremony commit created: ${commit_msg}"
        return 0
    else
        log_ceremony "No changes to commit"
        return 0
    fi
}

# Rollback on failure
rollback_ceremony() {
    log_error "Rolling back ceremony due to verification failure"
    
    # Reset to previous commit
    git reset --hard HEAD~1
    
    # Restore first-run flag if this was a first run
    if [[ -f "${STATE_DIR}/.firstrun.backup" ]]; then
        rm -f "${FIRST_RUN_FLAG}"
        log_ceremony "First-run flag restored for retry"
    fi
    
    log_audit "FAILURE: Ceremony rolled back"
}

# Main orchestration
main() {
    log_ceremony "=== Vault Sync Orchestrator Started ==="
    log_audit "START: Vault sync ceremony"
    
    # Check first run status
    local is_first="false"
    if is_first_run; then
        is_first="true"
        log_ceremony "FIRST RUN DETECTED - will mark all secrets as scrolls"
        touch "${STATE_DIR}/.firstrun.backup"
    else
        log_ceremony "Normal run - existing state detected"
    fi
    
    # Retrieve secrets from Vault
    if ! retrieve_secrets "${is_first}"; then
        log_error "Secret retrieval failed"
        exit 1
    fi
    
    # Generate manifest with checksums
    generate_manifest
    
    # Commit all artifacts atomically
    if ! commit_ceremony; then
        log_error "Commit ceremony failed"
        exit 1
    fi
    
    # Verify manifest integrity post-commit
    if ! verify_manifest; then
        rollback_ceremony
        exit 1
    fi
    
    # Mark first run complete
    if [[ "${is_first}" == "true" ]]; then
        mark_first_run_complete
        rm -f "${STATE_DIR}/.firstrun.backup"
    fi
    
    log_ceremony "=== Vault Sync Orchestrator Completed Successfully ==="
    log_audit "SUCCESS: Ceremony completed and verified"
}

main "$@"
