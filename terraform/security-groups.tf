# Security Group Configuration for Vault Server
# 
# This file defines firewall rules for the Vault EC2 instance.
# Access is restricted to GitHub Actions IP ranges for maximum security.

resource "aws_security_group" "vault" {
  name        = "${var.environment}-vault-sg"
  description = "Security group for Vault server - restricts access to GitHub Actions IPs"
  
  tags = {
    Name = "${var.environment}-vault-security-group"
  }
}

# Inbound rule: Allow Vault API access (port 8200) from GitHub Actions IPs
resource "aws_vpc_security_group_ingress_rule" "vault_api_github" {
  security_group_id = aws_security_group.vault.id
  description       = "Allow HTTPS access to Vault API from GitHub Actions"
  
  for_each = { for idx, cidr in local.github_actions_ips : idx => cidr }
  
  from_port   = 8200
  to_port     = 8200
  ip_protocol = "tcp"
  cidr_ipv4   = each.value
}

# Inbound rule: Allow SSH from specified CIDRs (emergency access only)
resource "aws_vpc_security_group_ingress_rule" "vault_ssh" {
  count = length(var.allowed_ssh_cidrs) > 0 ? 1 : 0
  
  security_group_id = aws_security_group.vault.id
  description       = "SSH access for emergency troubleshooting"
  
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr_ipv4   = var.allowed_ssh_cidrs[0]
}

# Outbound rule: Allow all egress (for package updates, Let's Encrypt, etc.)
resource "aws_vpc_security_group_egress_rule" "vault_egress" {
  security_group_id = aws_security_group.vault.id
  description       = "Allow all outbound traffic"
  
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}
