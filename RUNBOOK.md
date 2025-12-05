# Vault Sync Orchestrator Runbook

## Purpose
Operational runbook for first-run ingestion, AppRole rotation, rollback, emergency reset, and incident response for the Vault secret synchronization pipeline.

## Quick Reference Commands

### Force First-Run Ingestion
Trigger a complete re-ingestion of all secrets from Vault:
```bash
gh workflow run vault-sync.yml --ref main -f forcefirstrun=true
```

### Rollback Last Ceremony Commit
If verification fails or secrets are corrupted, rollback to previous state:
```bash
git fetch origin main
git reset --hard HEAD~1
git push --force-with-lease origin main
```

### Restore First-Run Flag
Force next run to treat all secrets as new scrolls:
```bash
touch orchestrator/state/firstrun.flag
git add orchestrator/state/firstrun.flag
git commit -m "Restore firstrun flag for re-ingestion"
git push origin main
```

### Emergency Reset Script
Use the provided utility script:
```bash
chmod +x orchestrator/reset-first-run.sh
./orchestrator/reset-first-run.sh
git add orchestrator/state/
git commit -m "Emergency: Reset first-run flag"
git push origin main
```

## AppRole Secret Rotation

### Generate New secret_id
```bash
vault write -format=json auth/approle/role/orchestrator/secret-id | \
  jq -r '.data.secret_id' > new_secret_id.txt
```

### Update GitHub Secret
```bash
gh secret set VAULT_APPROLE_SECRET_ID --body "$(cat new_secret_id.txt)"
# Securely delete temporary file
shred -u new_secret_id.txt
```

### Verify Workflow Login
Trigger a manual run to confirm authentication succeeds:
```bash
gh workflow run vault-sync.yml --ref main -f forcefirstrun=false
```
Check Actions logs for "Authenticate to Vault using AppRole" step success.

### Automated Rotation Script
Use the provided utility:
```bash
chmod +x orchestrator/rotate-approle-secret.sh
./orchestrator/rotate-approle-secret.sh
# Copy output value into GitHub Secrets manually or pipe to gh CLI
```

## Verification Steps After Each Run

### 1. Confirm Vault Authentication
Check GitHub Actions logs:
- "Authenticate to Vault using AppRole" step → SUCCESS
- Token policies should list: `["orchestrator"]`

### 2. Verify Metadata and Manifest
```bash
# Clone latest and inspect
git pull origin main
ls -la metadata/
cat manifest.json | jq '.secrets[] | {name, checksum}'
```

### 3. Run Local Manifest Verification
```bash
cd vault-sync-orchestrator
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="your-token"  # or use AppRole
./orchestrator/vault-sync.sh verify_manifest
```

### 4. Check Security Scan Results
Review "security-scan" job in Actions:
- No exposed secrets detected in `envs/`
- File permissions correct (no world/group readable)
- No GitHub issues created for security failures

## Incident Response Procedures

### Scenario: Manifest Verification Failure

**Symptoms**: Workflow fails at "Verify manifest integrity" step with checksum mismatches.

**Root Causes**:
- File corruption during commit
- Race condition with concurrent manual commit
- Disk I/O error on runner

**Response**:
1. **Automatic rollback** should have executed—verify with:
   ```bash
   git log -3 --oneline
   # Should NOT show failed ceremony commit
   ```

2. If rollback didn't execute, **manual rollback**:
   ```bash
   git reset --hard HEAD~1
   git push --force-with-lease origin main
   ```

3. **Check first-run flag status**:
   ```bash
   ls -la orchestrator/state/firstrun.flag
   # Should exist if this was a first run (automatic restore)
   ```

4. **Re-trigger workflow** with forced first-run if needed:
   ```bash
   gh workflow run vault-sync.yml --ref main -f forcefirstrun=true
   ```

5. **Escalate** if repeated failures occur (contact Platform/Security leads).

### Scenario: Secret Exposure Detected

**Symptoms**: "security-scan" job fails with "Potential secrets detected" error.

**Response**:
1. **Immediately revoke exposed secrets in Vault**:
   ```bash
   vault kv metadata delete secret/app/exposed-key
   ```

2. **Remove from repository history** (requires force push):
   ```bash
   # Use BFG Repo-Cleaner or git-filter-repo
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch envs/exposed.env" \
     --prune-empty --tag-name-filter cat -- --all
   git push --force --all
   ```

3. **Rotate all potentially compromised secrets**.

4. **Review security scan regex** and add suppression if false positive:
   - Document rationale in `SECURITY.md`
   - Update `.github/workflows/vault-sync.yml` exclusion patterns

5. **Notify Security team** immediately via `security@example.com` or PagerDuty.

### Scenario: AppRole Authentication Failure

**Symptoms**: "Authenticate to Vault using AppRole" step fails with 403 or invalid credentials.

**Root Causes**:
- `secret_id` expired (TTL: 10 minutes)
- `secret_id` already used (num_uses=1)
- GitHub Secret not updated after rotation
- Vault AppRole policy changed

**Response**:
1. **Generate fresh secret_id**:
   ```bash
   vault write -format=json auth/approle/role/orchestrator/secret-id | \
     jq -r '.data.secret_id'
   ```

2. **Update GitHub Secret immediately**:
   ```bash
   gh secret set VAULT_APPROLE_SECRET_ID --body "<new-secret-id>"
   ```

3. **Retry workflow**:
   ```bash
   gh workflow run vault-sync.yml --ref main
   ```

4. **Verify AppRole configuration**:
   ```bash
   vault read auth/approle/role/orchestrator
   # Check: token_policies=["orchestrator"], secret_id_ttl=10m, secret_id_num_uses=1
   ```

5. **Check policy permissions**:
   ```bash
   vault policy read orchestrator
   # Should allow read/list on secret/data/app/*
   ```

### Scenario: Concurrent Workflow Runs

**Symptoms**: Two workflow runs executing simultaneously, potential race condition.

**Prevention** (already implemented):
- Workflow has `concurrency` group preventing parallel runs
- `cancel-in-progress: false` ensures completion before retry

**If detected**:
1. **Cancel duplicate run** from Actions UI
2. **Wait for first run** to complete
3. **Verify no duplicate commits** were created
4. **Consider adding file-based locking** (flock) for additional safety

## Monitoring & Alerts

### Metrics to Track
- **Run Success Rate**: Target >99.5%
- **Manifest Verification Pass Rate**: Target 100%
- **Security Scan Failures**: Target 0
- **AppRole Auth Failures**: Target <1% (only during rotation windows)
- **Average Run Duration**: Baseline ~2-3 minutes

### Alert Configurations

**Critical Alerts** (immediate PagerDuty):
- Manifest verification failure
- Security scan detects exposed secrets
- 3 consecutive workflow failures

**Warning Alerts** (Slack notification):
- Single workflow failure
- Run duration >10 minutes
- AppRole authentication failure

**Info Notifications**:
- Successful first-run completion
- AppRole secret rotation completed

## Operational Contacts

| Role | Contact | Escalation |
|------|---------|------------|
| **Platform Lead** | platform@example.com | Primary on-call |
| **Security Lead** | security@example.com | Secret exposure incidents |
| **On-Call SRE** | pagerduty@example.com | After-hours emergencies |
| **Vault Admin** | vault-admin@example.com | AppRole/policy issues |

## Maintenance Windows

### Scheduled AppRole Rotation
- **Frequency**: Every 30 days
- **Window**: Tuesdays, 10:00-10:30 AM EST (low traffic)
- **Process**: Follow "AppRole Secret Rotation" section above
- **Verification**: Trigger test run within 1 hour

### Vault Secret Path Updates
When adding/removing secret paths:
1. Update `VAULT_SECRET_PATHS` GitHub Secret (space-separated)
2. Force first-run to ingest new paths:
   ```bash
   gh workflow run vault-sync.yml --ref main -f forcefirstrun=true
   ```
3. Verify new metadata files created in `metadata/`

## Testing & Validation

### Pre-Production Checklist
Before deploying to production:
- [ ] Local integration test passes
- [ ] Manifest verification passes
- [ ] Security scan passes with no false positives
- [ ] AppRole authentication succeeds
- [ ] Rollback procedure tested and verified
- [ ] CODEOWNERS file protects `orchestrator/` and `manifest.json`
- [ ] Branch protection requires status checks

### Staging Environment Test
```bash
# Set staging Vault and paths
gh secret set VAULT_ADDR --body "https://vault.staging.example.com"
gh secret set VAULT_SECRET_PATHS --body "secret/staging/app"

# Run full cycle
gh workflow run vault-sync.yml --ref main -f forcefirstrun=true

# Verify artifacts
git pull && ls -la envs/ metadata/ && cat manifest.json
```

## Security Best Practices

### Secret Handling
- **Never** log secret values in ceremony logs
- **Never** commit plaintext secrets to repository (use git-crypt if needed)
- **Always** use short-lived AppRole tokens (current: 1h TTL)
- **Rotate** AppRole secret_id every 30 days minimum
- **Audit** Vault access logs weekly for anomalies

### Access Control
- **Protect main branch**: Require PR reviews, status checks
- **CODEOWNERS**: Security team must approve orchestrator changes
- **GitHub Secrets**: Limit access to platform/security teams only
- **Vault Policy**: Grant minimum required permissions

### Encryption at Rest
Consider implementing:
- **git-crypt** for transparent `.env` encryption
- **sealed-secrets** for Kubernetes deployments
- **SOPS** for encrypted YAML/JSON storage

## Troubleshooting

### Debug Mode
Enable verbose logging in orchestrator:
```bash
# Edit vault-sync.sh temporarily
set -euxo pipefail  # Add 'x' for trace mode
```

### Local Execution
```bash
git clone git@github.com:Kypria-LLC/vault-sync-orchestrator.git
cd vault-sync-orchestrator

export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="test-token"
export VAULT_SECRET_PATHS="secret/test-app"

chmod +x orchestrator/vault-sync.sh
./orchestrator/vault-sync.sh
```

### Check Ceremony Logs
```bash
ls -lt logs/ceremony-*.log | head -1 | xargs cat
# Review for errors, timing issues, Vault responses
```

### Validate Manifest Checksums
```bash
for env in envs/*.env; do
  name=$(basename "$env" .env)
  actual=$(sha256sum "$env" | awk '{print $1}')
  expected=$(jq -r ".secrets[] | select(.name==\"$name\") | .checksum" manifest.json)
  echo "$name: expected=$expected actual=$actual"
done
```

## Disaster Recovery

### Complete Repository Restoration
If repository is corrupted beyond repair:
1. **Archive current state** for forensics
2. **Create fresh repository** from template
3. **Restore Vault secrets** to known-good state
4. **Force complete first-run**:
   ```bash
   rm -f orchestrator/state/firstrun.flag
   gh workflow run vault-sync.yml --ref main -f forcefirstrun=true
   ```

### Vault Outage Response
If Vault is unreachable:
1. Workflow will fail at Vault authentication—expected behavior
2. **No rollback needed** (no changes committed)
3. **Retry automatically** on next scheduled run (6 hours)
4. **Monitor Vault status** and coordinate with Vault team
5. **Do not force manual runs** until Vault is confirmed healthy

---

## Revision History

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2025-12-04 | 1.0 | Initial runbook creation | DevOps Team |

---

**Document Owner**: Platform Engineering Team  
**Last Reviewed**: 2025-12-04  
**Next Review**: 2026-01-04


---

## Incident Play Card for On-Call

**Purpose:** Quick reference for on-call to recover, rotate credentials, or re-run the first-run ingestion.

### Contact List
- **Platform lead:** platform@example.com
- **Security lead:** security@example.com
- **On-call SRE:** pagerduty@example.com

### Immediate Triage Steps

#### Check workflow status
```bash
# View latest workflow runs
gh run list --repo Kypria-LLC/vault-sync-orchestrator --limit 10
# Stream logs for a failing run
gh run view <run-id> --repo Kypria-LLC/vault-sync-orchestrator --log
```

#### If manifest verification failed: rollback
```bash
# Revert last commit that contains the ceremony commit
git fetch origin main
git checkout main
git reset --hard HEAD~1
git push --force-with-lease origin main
```

After rollback, restore first-run flag if you need to re-ingest:
```bash
touch orchestrator/state/firstrun.flag
git add orchestrator/state/firstrun.flag
git commit -m "Restore firstrun flag for re-ingestion"
git push origin main
```

#### If Vault AppRole secret_id is suspected compromised: rotate immediately
```bash
# Generate new secret_id locally (requires vault CLI and privileges)
./orchestrator/rotate-approle-secret.sh
# Copy printed secret_id and update GitHub secret
gh secret set VAULT_APPROLE_SECRET_ID --body "<new-secret-id>" --repo Kypria-LLC/vault-sync-orchestrator
# Optionally revoke old secret_id in Vault
```

#### Force a re-run of the orchestrator
```bash
gh workflow run vault-sync.yml --repo Kypria-LLC/vault-sync-orchestrator --ref main -f forcefirstrun=true
```

#### Emergency: remove first-run flag to force ingestion on next scheduled run
```bash
# Use helper script
chmod +x orchestrator/reset-first-run.sh
./orchestrator/reset-first-run.sh
# Commit if you want the change tracked
git add orchestrator/state/firstrun.flag || true
git commit -m "Emergency: remove firstrun flag" || true
git push origin main || true
```

### Verification Checklist After Recovery
- [ ] Vault auth step shows AppRole login success in workflow logs
- [ ] metadata/ contains scroll:true entries for first-run secrets
- [ ] manifest.json exists and checksums match files
- [ ] Atomic commit present with ceremony message and expected files staged
- [ ] Security scan shows no critical exposures
- [ ] Artifacts uploaded and accessible in Actions artifacts

### Escalation Rules
- **Within 15 minutes**: If rollback or rotation fails, notify Platform lead and Security lead via PagerDuty
- **Within 30 minutes**: If secrets exposure is confirmed, rotate all affected credentials and follow incident response playbook in RUNBOOK.md

### Short Commands Cheat Sheet
```bash
# Trigger manual run
gh workflow run vault-sync.yml --repo Kypria-LLC/vault-sync-orchestrator --ref main -f forcefirstrun=true

# Rollback last commit
git reset --hard HEAD~1
git push --force-with-lease origin main

# Restore first-run flag
touch orchestrator/state/firstrun.flag
git add orchestrator/state/firstrun.flag
git commit -m "Restore firstrun flag for re-ingestion"
git push origin main

# Rotate AppRole secret_id
./orchestrator/rotate-approle-secret.sh
gh secret set VAULT_APPROLE_SECRET_ID --body "<new-secret-id>" --repo Kypria-LLC/vault-sync-orchestrator
```
