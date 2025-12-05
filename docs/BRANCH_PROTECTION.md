# Branch Protection Automation

This script applies branch protection to the repository main branch.

## Required status checks
- vault-sync
- security-scan
- manifest-verification

## Review policy
- 2 approving reviews required
- CODEOWNERS review required
- Dismiss stale approvals on new commits

## Push restrictions
- Only platform-team, security-team, and GitHub Actions app allowed to push
- Force pushes and deletions disabled

## Run as org admin
- Ensure `gh` is authenticated as an org admin before running the script

## Usage

```bash
cd .github/scripts
chmod +x apply-branch-protection.sh
./apply-branch-protection.sh
```

The script will apply all branch protection rules to the main branch using the GitHub CLI.
