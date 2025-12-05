# 🛠 Vault Admin Checklist — AppRole Setup for GitHub Actions

**Purpose:** Generate AppRole credentials for the vault-sync-orchestrator GitHub Actions workflow.

**Time Required:** 5-10 minutes

**Date:** Friday, December 5, 2025

---

## Prerequisites

- [ ] Vault CLI installed and accessible
- [ ] Admin/root access to Vault server
- [ ] `jq` installed (for JSON parsing)
- [ ] Access to GitHub repository settings

---

## Step 1: Log in to Vault

Verify you're authenticated as a Vault admin:

```bash
vault status
vault login <admin-token>
```

**Expected output:** Vault should show as initialized and unsealed.

---

## Step 2: Create a Policy

Create a file named `vault-sync-policy.hcl` with read access to the secret paths you want synced:

```hcl
# vault-sync-policy.hcl
# CUSTOMIZE these paths to match your actual secret locations

path "secret/data/app1/*" {
  capabilities = ["read", "list"]
}

path "secret/data/db-creds/*" {
  capabilities = ["read", "list"]
}

path "secret/data/api-keys/*" {
  capabilities = ["read", "list"]
}

# Add more paths as needed for your environment
```

**Apply the policy:**

```bash
vault policy write vault-sync-policy vault-sync-policy.hcl
```

**Expected output:**
```
Success! Uploaded policy: vault-sync-policy
```

---

## Step 3: Create the AppRole

Run the following command to create the AppRole with appropriate token TTLs:

```bash
vault write auth/approle/role/vault-sync-orchestrator \
  token_policies="vault-sync-policy" \
  token_ttl="1h" \
  token_max_ttl="4h" \
  secret_id_ttl="720h" \
  secret_id_num_uses=0
```

**Parameter Explanation:**
- `token_ttl="1h"` - Access tokens valid for 1 hour
- `token_max_ttl="4h"` - Maximum token lifetime (including renewals)
- `secret_id_ttl="720h"` - Secret ID valid for 30 days (720 hours)
- `secret_id_num_uses=0` - Secret ID can be used unlimited times

**Expected output:**
```
Success! Data written to: auth/approle/role/vault-sync-orchestrator
```

---

## Step 4: Retrieve the Role ID

Generate the Role ID (this is like a username for the AppRole):

```bash
vault read -format=json auth/approle/role/vault-sync-orchestrator/role-id | jq -r '.data.role_id'
```

**Expected output:** A UUID string like:
```
e3f1a2b4-5678-90ab-cdef-1234567890ab
```

✅ **ACTION REQUIRED:** Copy this string - you'll add it to GitHub as `VAULT_APPROLE_ROLE_ID`

---

## Step 5: Generate a Secret ID

Generate the Secret ID (this is like a password for the AppRole):

```bash
vault write -format=json -f auth/approle/role/vault-sync-orchestrator/secret-id | jq -r '.data.secret_id'
```

**Expected output:** A UUID string like:
```
9c8d7e6f-1234-5678-90ab-fedcba098765
```

✅ **ACTION REQUIRED:** Copy this string - you'll add it to GitHub as `VAULT_APPROLE_SECRET_ID`

⚠️ **SECURITY WARNING:** Treat the Secret ID like a password. Never commit it to version control.

---

## Step 6: Verify AppRole Access

(Optional but recommended) Test that the AppRole can authenticate and read secrets:

```bash
# Export the credentials
export ROLE_ID="<your-role-id-from-step-4>"
export SECRET_ID="<your-secret-id-from-step-5>"

# Authenticate
VAULT_TOKEN=$(vault write -format=json auth/approle/login \
  role_id="$ROLE_ID" \
  secret_id="$SECRET_ID" | jq -r '.auth.client_token')

# Test reading a secret
VAULT_TOKEN=$VAULT_TOKEN vault kv get secret/app1/config
```

**Expected output:** The secret data should be displayed successfully.

---

## Step 7: Add Credentials to GitHub Actions Secrets

Now that you have the Role ID and Secret ID, add them to GitHub:

### Method 1: Using GitHub Web UI

1. Go to: https://github.com/Kypria-LLC/vault-sync-orchestrator/settings/secrets/actions
2. Click **"New repository secret"**
3. Add each of the following secrets:

| Secret Name | Value |
|-------------|-------|
| `VAULT_ADDR` | Your Vault server URL (e.g., `https://vault.yourdomain.com:8200`) |
| `VAULT_NAMESPACE` | Your Vault namespace (e.g., `admin`) - leave blank if using Vault OSS |
| `VAULT_SECRET_PATHS` | Comma-separated secret paths (e.g., `secret/data/app1,secret/data/db-creds`) |
| `VAULT_APPROLE_ROLE_ID` | The Role ID from Step 4 |
| `VAULT_APPROLE_SECRET_ID` | The Secret ID from Step 5 |

### Method 2: Using GitHub CLI

```bash
# Replace placeholder values with your actual values
gh secret set VAULT_ADDR --body "https://vault.yourdomain.com:8200" --repo Kypria-LLC/vault-sync-orchestrator
gh secret set VAULT_NAMESPACE --body "admin" --repo Kypria-LLC/vault-sync-orchestrator
gh secret set VAULT_SECRET_PATHS --body "secret/data/app1,secret/data/db-creds" --repo Kypria-LLC/vault-sync-orchestrator
gh secret set VAULT_APPROLE_ROLE_ID --body "<role-id-from-step-4>" --repo Kypria-LLC/vault-sync-orchestrator
gh secret set VAULT_APPROLE_SECRET_ID --body "<secret-id-from-step-5>" --repo Kypria-LLC/vault-sync-orchestrator
```

### Verify Secrets Were Added

```bash
gh secret list --repo Kypria-LLC/vault-sync-orchestrator
```

**Expected output:** All 5 secrets should be listed.

---

## Step 8: Trigger First Production Run

Once all secrets are configured, trigger the initial workflow run:

```bash
gh workflow run vault-sync.yml --repo Kypria-LLC/vault-sync-orchestrator --ref main -f forcefirstrun=true
```

**Monitor the workflow:**

```bash
gh run watch --repo Kypria-LLC/vault-sync-orchestrator
```

---

## ✅ Success Indicators

After the workflow completes, you should see:

- ✅ Green checkmark in GitHub Actions tab
- ✅ New ceremony commit in git history
- ✅ First-run flag cleared (`.first_run_complete` file created)
- ✅ Manifest checksums validate successfully
- ✅ No errors in workflow logs

---

## 🔄 AppRole Rotation Schedule

**IMPORTANT:** Rotate the Secret ID regularly for security best practices.

**Recommended schedule:** Every 30 days

**To rotate the Secret ID:**

```bash
# Generate new Secret ID
NEW_SECRET_ID=$(vault write -format=json -f auth/approle/role/vault-sync-orchestrator/secret-id | jq -r '.data.secret_id')

# Update GitHub secret
gh secret set VAULT_APPROLE_SECRET_ID --body "$NEW_SECRET_ID" --repo Kypria-LLC/vault-sync-orchestrator

echo "✅ Secret ID rotated successfully"
```

**Set a calendar reminder:** Rotate on the 1st of each month.

---

## 🚨 Emergency Recovery

### If Secret ID is Compromised

1. **Immediately revoke all Secret IDs:**
   ```bash
   vault write -f auth/approle/role/vault-sync-orchestrator/secret-id-accessor/destroy \
     secret_id_accessor=<accessor-id>
   ```

2. **Generate new Secret ID** (repeat Step 5)

3. **Update GitHub secret** (repeat Step 7)

### If AppRole is Locked Out

1. **Check policy attachments:**
   ```bash
   vault read auth/approle/role/vault-sync-orchestrator
   ```

2. **Re-apply policy if needed:**
   ```bash
   vault write auth/approle/role/vault-sync-orchestrator token_policies="vault-sync-policy"
   ```

---

## 📞 Support Resources

- **Repository Documentation:** https://github.com/Kypria-LLC/vault-sync-orchestrator
- **Runbook:** `RUNBOOK.md` in repository root
- **Branch Protection Docs:** `docs/BRANCH_PROTECTION.md`
- **Vault AppRole Docs:** https://developer.hashicorp.com/vault/docs/auth/approle

---

## Summary

You've successfully:

✅ Created a Vault policy with read access to secrets  
✅ Created an AppRole with secure token TTLs  
✅ Generated Role ID and Secret ID credentials  
✅ Added all required GitHub Actions secrets  
✅ Verified AppRole access (optional)  
✅ Ready to trigger first production run  

**Next step:** Trigger the workflow and monitor the first ceremony run.

**Estimated time to production:** 1-2 minutes after triggering workflow.

---

**Generated:** December 5, 2025  
**Maintainer:** Kypria LLC Security Team  
**Version:** 1.0
