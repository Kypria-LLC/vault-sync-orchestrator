#!/usr/bin/env bash
set -euo pipefail

# Generate a new AppRole secret_id for the orchestrator role and print it.
# NOTE: This script requires the vault CLI and appropriate privileges to create secret_ids.
# After running, copy the printed secret_id into GitHub Actions secret VAULT_APPROLE_SECRET_ID.

if ! command -v vault >/dev/null 2>&1; then
  echo "vault CLI not found. Install the Vault CLI and authenticate before running." >&2
  exit 2
fi

ROLE_PATH="auth/approle/role/orchestrator/secret-id"

echo "Generating new secret_id for AppRole 'orchestrator'..."
new_secret=$(vault write -format=json "$ROLE_PATH" | jq -r '.data.secret_id')

if [ -z "$new_secret" ] || [ "$new_secret" = "null" ]; then
  echo "Failed to generate secret_id. Check Vault permissions and connectivity." >&2
  exit 3
fi

cat <<EOF
New secret_id generated.
Copy this value into GitHub Actions secret: VAULT_APPROLE_SECRET_ID

${new_secret}
EOF
