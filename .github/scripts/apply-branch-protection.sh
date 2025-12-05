#!/usr/bin/env bash
set -euo pipefail

# Usage: ./apply-branch-protection.sh Kypria-LLC vault-sync-orchestrator main
ORG="${1:-Kypria-LLC}"
REPO="${2:-vault-sync-orchestrator}"
BRANCH="${3:-main}"

REPO_FULL="${ORG}/${REPO}"

# Required status checks contexts must match workflow job names
REQUIRED_CONTEXTS=("vault-sync" "security-scan" "manifest-verification")

# Convert contexts to JSON array string
contexts_json=$(printf '%s\n' "${REQUIRED_CONTEXTS[@]}" | jq -R . | jq -s .)

echo "Applying branch protection to ${REPO_FULL} branch ${BRANCH}"
echo "Required contexts: ${REQUIRED_CONTEXTS[*]}"

gh api --method PUT /repos/"${REPO_FULL}"/branches/"${BRANCH}"/protection \
  -f required_status_checks="$(jq -n --argjson ctx "${contexts_json}" '{"strict":true,"contexts":$ctx}')" \
  -f enforce_admins=false \
  -f required_pull_request_reviews='{"dismiss_stale_reviews":true,"required_approving_review_count":2,"require_code_owner_reviews":true}' \
  -f restrictions='{"users":[],"teams":["platform-team","security-team"],"apps":["github-actions"]}' \
  -f required_linear_history=true \
  -f allow_force_pushes=false \
  -f allow_deletions=false

echo "Branch protection applied to ${REPO_FULL}:${BRANCH}"
