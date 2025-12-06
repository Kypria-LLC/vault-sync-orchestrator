# Production Vault Deployment - Terraform Module

This Terraform module deploys a production-grade HashiCorp Vault server on AWS for the vault-sync-orchestrator secret synchronization pipeline.

## Architecture

- **Compute**: Single EC2 instance (t3.medium) running Vault v1.21.1
- **Storage**: Raft integrated storage on encrypted EBS volume (50GB gp3)
- **TLS**: Automatic certificate management via Let's Encrypt (DNS-01 challenge with Route53)
- **Authentication**: AppRole with 30-day Secret ID rotation
- **Security**: Security group restricts access to GitHub Actions IP ranges only
- **Audit**: CloudWatch Logs integration with 90-day retention

## Prerequisites

1. AWS Account with appropriate permissions
2. Registered domain name for Vault
3. Route53 hosted zone (created automatically by this module)
4. SSH key pair for emergency access
5. Terraform >= 1.0

## Usage

### 1. Configuration

Copy the example variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
aws_region       = "us-east-1"
env ironment      = "production"
vault_domain     = "vault.your-domain.com"
ssh_key_name     = "your-ec2-key"
vault_secret_paths = "secret/data/app1,secret/data/db-creds"
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 3. Configure DNS

After deployment, configure nameservers at your domain registrar using the values from:

```bash
terraform output route53_nameservers
```

### 4. Retrieve Credentials

Credentials are automatically stored in AWS SSM Parameter Store:

```bash
# Get Vault address
aws ssm get-parameter --name "/production/vault/addr" --query "Parameter.Value" --output text

# Get Role ID (encrypted)
aws ssm get-parameter --name "/production/vault/role-id" --with-decryption --query "Parameter.Value" --output text

# Get Secret ID (encrypted)
aws ssm get-parameter --name "/production/vault/secret-id" --with-decryption --query "Parameter.Value" --output text
```

### 5. Update GitHub Secrets

Update the following secrets in your GitHub repository:

- `VAULT_ADDR`: Retrieved from SSM
- `VAULT_APPROLE_ROLE_ID`: Retrieved from SSM
- `VAULT_APPROLE_SECRET_ID`: Retrieved from SSM
- `VAULT_NAMESPACE`: (empty for OSS Vault)
- `VAULT_SECRET_PATHS`: Configured secret paths

## Security Features

- **TLS Encryption**: All Vault API traffic uses HTTPS with automatic certificate renewal
- **Network Isolation**: Security group restricts access to GitHub Actions IP ranges
- **EBS Encryption**: All storage volumes encrypted with AWS KMS
- **IMDSv2**: EC2 metadata service v2 enforced
- **Audit Logging**: All Vault operations logged to CloudWatch
- **Secret Rotation**: AppRole Secret ID has 30-day TTL with mandatory rotation

## Maintenance

### Secret ID Rotation

Rotate the Secret ID every 30 days:

```bash
vault write -force auth/approle/role/github-actions-sync/secret-id
aws ssm put-parameter --name "/production/vault/secret-id" --value "NEW_SECRET_ID" --type SecureString --overwrite
```

Update the GitHub secret `VAULT_APPROLE_SECRET_ID` with the new value.

### TLS Certificate Renewal

Certificates are automatically renewed by certbot. Check renewal status:

```bash
ssh -i your-key.pem ubuntu@$(terraform output -raw vault_public_ip)
sudo certbot renew --dry-run
```

## Troubleshooting

### Check Vault Status

```bash
export VAULT_ADDR=$(terraform output -raw vault_address)
vault status
```

### View Audit Logs

Access CloudWatch Logs via AWS Console or CLI:

```bash
aws logs tail /aws/vault/production/audit --follow
```

### SSH Access

For emergency troubleshooting:

```bash
ssh -i your-key.pem ubuntu@$(terraform output -raw vault_public_ip)
```

## Files

- `main.tf`: Core AWS resources (EC2, IAM, KMS, Route53)
- `variables.tf`: Input variables and validation rules
- `outputs.tf`: Output values and deployment instructions
- `security-groups.tf`: Firewall rules for Vault access
- `user-data.sh`: EC2 initialization script
- `terraform.tfvars.example`: Configuration template

## Support

For issues or questions, contact the infrastructure team or refer to the main vault-sync-orchestrator documentation.
