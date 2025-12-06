# Terraform Outputs for Production Vault Deployment
# 
# These outputs provide essential information needed to configure GitHub Actions secrets.
# Values are stored in AWS SSM Parameter Store for secure retrieval by infrastructure team.

output "vault_address" {
  description = "Vault server HTTPS address (for VAULT_ADDR GitHub secret)"
  value       = "https://${var.vault_domain}:8200"
}

output "vault_public_ip" {
  description = "Public IP address of the Vault EC2 instance"
  value       = aws_eip.vault.public_ip
}

output "vault_instance_id" {
  description = "EC2 instance ID for Vault server"
  value       = aws_instance.vault.id
}

output "route53_nameservers" {
  description = "Route53 nameservers to configure at domain registrar"
  value       = aws_route53_zone.vault.name_servers
}

output "ssm_parameter_paths" {
  description = "AWS SSM Parameter Store paths containing Vault credentials"
  value = {
    vault_addr      = aws_ssm_parameter.vault_addr.name
    role_id         = aws_ssm_parameter.vault_role_id.name
    secret_id       = aws_ssm_parameter.vault_secret_id.name
    namespace       = aws_ssm_parameter.vault_namespace.name
    secret_paths    = aws_ssm_parameter.vault_secret_paths.name
  }
}

output "deployment_instructions" {
  description = "Post-deployment steps for infrastructure team"
  value = <<-EOT
    
    Deployment Complete!
    ====================
    
    Next Steps for Infrastructure Team:
    
    1. DNS Configuration
       Configure nameservers at your domain registrar:
       ${join("\n       ", aws_route53_zone.vault.name_servers)}
    
    2. Wait for DNS Propagation
       Verify DNS resolution: dig ${var.vault_domain}
    
    3. Retrieve Vault Credentials from AWS SSM Parameter Store
       
       # Option A: Using AWS Console
       Navigate to: Systems Manager → Parameter Store
       Retrieve these 5 parameters:
       - ${aws_ssm_parameter.vault_addr.name}
       - ${aws_ssm_parameter.vault_role_id.name}
       - ${aws_ssm_parameter.vault_secret_id.name}
       - ${aws_ssm_parameter.vault_namespace.name}
       - ${aws_ssm_parameter.vault_secret_paths.name}
       
       # Option B: Using AWS CLI
       aws ssm get-parameter --name "${aws_ssm_parameter.vault_addr.name}" --query "Parameter.Value" --output text
       aws ssm get-parameter --name "${aws_ssm_parameter.vault_role_id.name}" --with-decryption --query "Parameter.Value" --output text
       aws ssm get-parameter --name "${aws_ssm_parameter.vault_secret_id.name}" --with-decryption --query "Parameter.Value" --output text
       aws ssm get-parameter --name "${aws_ssm_parameter.vault_namespace.name}" --query "Parameter.Value" --output text
       aws ssm get-parameter --name "${aws_ssm_parameter.vault_secret_paths.name}" --query "Parameter.Value" --output text
    
    4. Provide Credentials to Alexander via Secure Channel
       Send the 5 values retrieved from SSM Parameter Store:
       - VAULT_ADDR
       - VAULT_APPROLE_ROLE_ID
       - VAULT_APPROLE_SECRET_ID
       - VAULT_NAMESPACE
       - VAULT_SECRET_PATHS
    
    5. Alexander Updates GitHub Secrets
       Navigate to: Repository Settings → Secrets and variables → Actions
       Update all 5 secrets with production values
    
    6. Alexander Triggers First Workflow Run
       gh workflow run vault-sync.yml -f force_first_run=true
    
    7. Alexander Rotates Secret ID Immediately
       After first successful run, rotate the Secret ID:
       vault write -force auth/approle/role/github-actions-sync/secret-id
       
       Then update the VAULT_APPROLE_SECRET_ID GitHub secret
    
    8. Set Rotation Reminder
       Secret ID TTL: 30 days
       Next rotation due: ${timeadd(timestamp(), "720h")}
       Set calendar reminder for: ${formatdate("YYYY-MM-DD", timeadd(timestamp(), "720h"))}
    
    Security Notes:
    - Vault EC2 instance: ${aws_instance.vault.id}
    - Security group restricts access to GitHub Actions IP ranges only
    - All connections use TLS (certificate auto-renewed via Let's Encrypt)
    - Audit logs enabled: ${aws_cloudwatch_log_group.vault_audit.name}
    - EBS volumes encrypted with: ${aws_kms_key.vault.arn}
    
    Troubleshooting:
    - EC2 Console: https://console.aws.amazon.com/ec2/v2/home?region=${var.aws_region}#Instances:instanceId=${aws_instance.vault.id}
    - CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.vault_audit.name, "/", "$252F")}
    - SSM Parameters: https://console.aws.amazon.com/systems-manager/parameters?region=${var.aws_region}
    
  EOT
}
