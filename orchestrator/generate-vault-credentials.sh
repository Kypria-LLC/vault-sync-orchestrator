#!/bin/bash
# Vault AppRole Credential Generator for vault-sync-orchestrator
# Run this script on a Vault-authenticated host with admin access
# 
# Purpose: Generate AppRole credentials for GitHub Actions workflow
# Time Required: 5-10 minutes
# Date: December 5, 2025

set -euo pipefail

echo "🔐 Vault AppRole Credential Generator"
echo "======================================"
echo ""
echo "This script will:"
echo "  1. Verify Vault connection"
echo "  2. Create a read-only policy"
echo "  3. Create an AppRole"
echo "  4. Generate Role ID and Secret ID"
echo "  5. Output credentials for GitHub Actions"
echo ""

# Step 1: Verify Vault connection
echo "Step 1: Verifying Vault connection..."
if ! vault status &>/dev/null; then
    echo "❌ ERROR: Cannot connect to Vault. Please authenticate first:"
    echo "   vault login <admin-token>"
    echo ""
    echo "Or set VAULT_ADDR and VAULT_TOKEN environment variables:"
    echo "   export VAULT_ADDR=https://vault.yourdomain.com:8200"
    echo "   export VAULT_TOKEN=<your-admin-token>"
    exit 1
fi
echo "✅ Vault connection verified"
echo "   Vault Address: ${VAULT_ADDR:-<not set>}"
echo ""

# Step 2: Create policy
echo "Step 2: Creating vault-sync-policy..."
echo "   This policy grants read-only access to secrets"
echo ""

# Prompt for secret paths
echo "Enter the secret paths you want to sync (comma-separated):"
echo "Example: secret/data/app1,secret/data/db-creds,secret/data/api-keys"
read -p "Secret paths: " SECRET_PATHS

if [ -z "$SECRET_PATHS" ]; then
    echo "❌ ERROR: Secret paths cannot be empty"
    exit 1
fi

# Convert comma-separated paths to policy format
POLICY_CONTENT='# Vault Sync Policy - Read-only access to secrets
# Generated: '$(date)'
'

IFS=',' read -ra PATHS <<< "$SECRET_PATHS"
for path in "${PATHS[@]}"; do
    # Trim whitespace
    path=$(echo "$path" | xargs)
    POLICY_CONTENT+="
path \"$path/*\" {
  capabilities = [\"read\", \"list\"]
}
"
done

# Write policy to temp file
echo "$POLICY_CONTENT" > /tmp/vault-sync-policy.hcl

# Apply the policy
vault policy write vault-sync-policy /tmp/vault-sync-policy.hcl
if [ $? -eq 0 ]; then
    echo "✅ Policy created successfully"
else
    echo "❌ ERROR: Failed to create policy"
    exit 1
fi
echo ""

# Step 3: Create AppRole
echo "Step 3: Creating AppRole..."
echo "   Token TTL: 1 hour"
echo "   Token Max TTL: 4 hours"
echo "   Secret ID TTL: 30 days (720 hours)"
echo ""

vault write auth/approle/role/vault-sync-orchestrator \
    token_policies="vault-sync-policy" \
    token_ttl="1h" \
    token_max_ttl="4h" \
    secret_id_ttl="720h" \
    secret_id_num_uses=0

if [ $? -eq 0 ]; then
    echo "✅ AppRole created successfully"
else
    echo "❌ ERROR: Failed to create AppRole"
    exit 1
fi
echo ""

# Step 4: Retrieve Role ID
echo "Step 4: Retrieving Role ID..."
ROLE_ID=$(vault read -format=json auth/approle/role/vault-sync-orchestrator/role-id 2>/dev/null | jq -r '.data.role_id')

if [ -z "$ROLE_ID" ] || [ "$ROLE_ID" = "null" ]; then
    echo "❌ ERROR: Failed to retrieve Role ID"
    exit 1
fi
echo "✅ Role ID retrieved"
echo ""

# Step 5: Generate Secret ID
echo "Step 5: Generating Secret ID..."
SECRET_ID=$(vault write -format=json -f auth/approle/role/vault-sync-orchestrator/secret-id 2>/dev/null | jq -r '.data.secret_id')

if [ -z "$SECRET_ID" ] || [ "$SECRET_ID" = "null" ]; then
    echo "❌ ERROR: Failed to generate Secret ID"
    exit 1
fi
echo "✅ Secret ID generated"
echo ""

# Step 6: Test AppRole authentication (optional)
echo "Step 6: Testing AppRole authentication..."
TEST_TOKEN=$(vault write -format=json auth/approle/login \
    role_id="$ROLE_ID" \
    secret_id="$SECRET_ID" 2>/dev/null | jq -r '.auth.client_token')

if [ -z "$TEST_TOKEN" ] || [ "$TEST_TOKEN" = "null" ]; then
    echo "⚠️  WARNING: AppRole authentication test failed"
    echo "   Credentials may still work, but verification failed"
else
    echo "✅ AppRole authentication successful"
fi
echo ""

# Step 7: Output credentials
echo "======================================"
echo "🎉 CREDENTIALS GENERATED SUCCESSFULLY"
echo "======================================"
echo ""
echo "Add these 5 values to GitHub Actions secrets:"
echo "https://github.com/Kypria-LLC/vault-sync-orchestrator/settings/secrets/actions"
echo ""
echo "───────────────────────────────────────"
echo "1. VAULT_ADDR"
echo "───────────────────────────────────────"
echo "${VAULT_ADDR}"
echo ""
echo "───────────────────────────────────────"
echo "2. VAULT_NAMESPACE"
echo "───────────────────────────────────────"
if [ -z "${VAULT_NAMESPACE:-}" ]; then
    echo "(leave blank - not using Vault Enterprise namespaces)"
else
    echo "${VAULT_NAMESPACE}"
fi
echo ""
echo "───────────────────────────────────────"
echo "3. VAULT_SECRET_PATHS"
echo "───────────────────────────────────────"
echo "$SECRET_PATHS"
echo ""
echo "───────────────────────────────────────"
echo "4. VAULT_APPROLE_ROLE_ID"
echo "───────────────────────────────────────"
echo "$ROLE_ID"
echo ""
echo "───────────────────────────────────────"
echo "5. VAULT_APPROLE_SECRET_ID"
echo "───────────────────────────────────────"
echo "$SECRET_ID"
echo ""
echo "======================================"
echo "⚠️  SECURITY REMINDERS"
echo "======================================"
echo "• Treat Secret ID like a password"
echo "• Secret ID expires in 30 days (720 hours)"
echo "• Rotation automation is already configured"
echo "• Never commit secrets to git"
echo "• Use encrypted GitHub Actions secrets only"
echo ""
echo "======================================"
echo "📋 NEXT STEPS"
echo "======================================"
echo "1. Copy the 5 values above"
echo "2. Navigate to GitHub repository settings"
echo "3. Update each secret (click edit icon)"
echo "4. Trigger first production workflow run"
echo "5. Set first_run: true in workflow dispatch"
echo "6. Monitor workflow execution (~45-60 seconds)"
echo "7. Verify ceremony success (green checkmarks)"
echo "8. ⚠️  IMMEDIATELY rotate Secret ID (mandatory)"
echo "9. Set calendar reminder for Jan 4, 2026"
echo ""
echo "✅ Credential generation completed successfully"
echo "   Generated: $(date)"
echo "   Vault Address: ${VAULT_ADDR}"
echo "   Policy: vault-sync-policy"
echo "   AppRole: vault-sync-orchestrator"
echo ""
