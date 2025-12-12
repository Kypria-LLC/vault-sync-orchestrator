# Production Terraform Deployment Templates
## vault-sync-orchestrator - Enterprise Edition

🎉 **Thank you for your purchase!**

You now have access to production-grade Terraform templates for deploying HashiCorp Vault infrastructure optimized for the vault-sync-orchestrator secret synchronization pipeline.

---

## 📦 What's Included

This package contains everything you need to deploy a secure, production-ready Vault server:

### Terraform Infrastructure Files
- `main.tf` - Core AWS resources (EC2, IAM, KMS, Route53)
- `variables.tf` - Input variables and validation rules
- `outputs.tf` - Output values and deployment instructions  
- `security-groups.tf` - Firewall rules for Vault access
- `user-data.sh` - EC2 initialization script
- `terraform.tfvars.example` - Configuration template

### Documentation
- `README.md` - Comprehensive deployment guide
- Architecture diagrams
- Security features overview
- Maintenance and troubleshooting guides

### Enterprise Features
✅ **Single EC2 instance** (t3.medium) running Vault v1.21.1  
✅ **Raft integrated storage** on encrypted EBS volume (50GB gp3)  
✅ **Automatic TLS** via Let's Encrypt (DNS-01 challenge with Route53)  
✅ **AppRole authentication** with 30-day Secret ID rotation  
✅ **Security group** restricts access to GitHub Actions IP ranges only  
✅ **CloudWatch Logs** integration with 90-day retention  
✅ **IMDSv2 enforced** for EC2 metadata security

---

## 🚀 Quick Start

### Prerequisites
1. AWS Account with appropriate permissions
2. Terraform >= 1.0
3. Domain hosted on Route53
4. GitHub repository for vault-sync-orchestrator

### Deployment Steps

```bash
# 1. Clone or copy the terraform files to your local machine
cd products/terraform-templates

# 2. Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Initialize Terraform
terraform init

# 4. Review the plan
terraform plan

# 5. Deploy
terraform apply

# 6. Retrieve credentials from AWS SSM Parameter Store
aws ssm get-parameter --name "/production/vault/addr" --query "Parameter.Value"
aws ssm get-parameter --name "/production/vault/role-id" --with-decryption --query "Parameter.Value"
aws ssm get-parameter --name "/production/vault/secret-id" --with-decryption --query "Parameter.Value"
```

---

## 🔒 Security Best Practices

This template implements industry-standard security practices:

- **TLS Encryption**: All Vault API traffic uses HTTPS with automatic certificate renewal
- **Network Isolation**: Security group restricts access to GitHub Actions IP ranges
- **EBS Encryption**: All storage volumes encrypted with AWS KMS
- **IMDSv2**: EC2 metadata service v2 enforced
- **Audit Logging**: All Vault operations logged to CloudWatch
- **Secret Rotation**: AppRole Secret ID has 30-day TTL with mandatory rotation

---

## 📚 Additional Resources

### Documentation
- Full README.md with architecture details
- Step-by-step deployment guide
- Troubleshooting section
- Maintenance procedures

### Support
For issues or questions:
1. Check the README.md troubleshooting section
2. Review CloudWatch logs: `aws logs tail /aws/vault/production/audit --follow`
3. Contact: support@kypria-llc.com

### Updates
As a customer, you receive:
- Lifetime access to this version
- Free updates for 1 year
- Priority email support

---

## 💡 Next Steps

1. ✅ Deploy the Terraform infrastructure
2. ✅ Configure GitHub Secrets with Vault credentials
3. ✅ Set up vault-sync-orchestrator pipeline
4. ✅ Test secret synchronization
5. ✅ Set up monitoring and alerts

---

## 🔗 Related Products

**Vault Security Audit Checklist** ($19/mo)  
Comprehensive security checklist for production Vault deployments

**Vault Sync Quick-Start Deployment Guide** ($75/mo)  
Step-by-step video tutorials and scripts for faster deployment

**Enterprise Support Package** ($499/mo)  
White-glove support with dedicated engineer

---

## 📄 License

This product is licensed for use by the purchasing organization only. Redistribution is prohibited.

**License Type**: Single Organization  
**Purchase Date**: [Automatically generated]  
**Licensed To**: [Customer email from Stripe]

---

**Kypria LLC** - Enterprise DevSecOps Infrastructure Solutions  
© 2024 All Rights Reserved

For support: support@kypria-llc.com  
Website: https://kypria-llc.com
