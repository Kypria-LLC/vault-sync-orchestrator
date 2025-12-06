terraform/main.tf# Production HashiCorp Vault Deployment on AWS
# 
# This Terraform module deploys a production-grade Vault server for the
# vault-sync-orchestrator secret synchronization pipeline.
#
# Architecture:
# - Single EC2 instance (t3.medium) running Vault v1.21.1
# - Raft integrated storage backend (persistent EBS volume)
# - TLS via Let's Encrypt (automatic certificate management)
# - Security group restricting access to GitHub Actions IP ranges
# - Automatic initialization and unseal on first boot
# - Audit logging enabled
# - AppRole authentication configured
# - Credentials output to AWS SSM Parameter Store

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "vault-sync-orchestrator"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Owner       = "infrastructure-team"
    }
  }
}

# Data source for GitHub Actions IP ranges
data "http" "github_meta" {
  url = "https://api.github.com/meta"
}

locals {
  github_actions_ips = jsondecode(data.http.github_meta.response_body)["actions"]
}

# IAM Role for EC2 instance
resource "aws_iam_role" "vault" {
  name = "${var.environment}-vault-ec2-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.environment}-vault-ec2-role"
  }
}

# IAM Policy for Vault operations
resource "aws_iam_role_policy" "vault" {
  name = "${var.environment}-vault-policy"
  role = aws_iam_role.vault.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSSMParameterAccess"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.environment}/vault/*"
      },
      {
        Sid    = "AllowKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.vault.arn
      },
      {
        Sid    = "AllowRoute53Updates"
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:ListHostedZones"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowRoute53CertificateValidation"
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${aws_route53_zone.vault.zone_id}"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "vault" {
  name = "${var.environment}-vault-instance-profile"
  role = aws_iam_role.vault.name

  tags = {
    Name = "${var.environment}-vault-instance-profile"
  }
}

# KMS Key for EBS encryption
resource "aws_kms_key" "vault" {
  description             = "${var.environment} Vault EBS encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.environment}-vault-ebs-key"
  }
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.environment}-vault-ebs"
  target_key_id = aws_kms_key.vault.key_id
}

# Route53 Hosted Zone for Vault domain
resource "aws_route53_zone" "vault" {
  name = var.vault_domain

  tags = {
    Name = "${var.environment}-vault-zone"
  }
}

# Route53 A Record pointing to Vault EC2
resource "aws_route53_record" "vault" {
  zone_id = aws_route53_zone.vault.zone_id
  name    = var.vault_domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.vault.public_ip]
}

# Elastic IP for stable addressing
resource "aws_eip" "vault" {
  domain = "vpc"
  
  tags = {
    Name = "${var.environment}-vault-eip"
  }
}

resource "aws_eip_association" "vault" {
  instance_id   = aws_instance.vault.id
  allocation_id = aws_eip.vault.id
}

# EC2 Instance for Vault
resource "aws_instance" "vault" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name              = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.vault.id]
  iam_instance_profile   = aws_iam_instance_profile.vault.name
  
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # Enforce IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
  
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    kms_key_id           = aws_kms_key.vault.arn
    delete_on_termination = false  # Preserve for disaster recovery
    
    tags = {
      Name = "${var.environment}-vault-root"
    }
  }
  
  user_data = templatefile("${path.module}/user-data.sh", {
    vault_version     = var.vault_version
    vault_domain      = var.vault_domain
    aws_region        = var.aws_region
    environment       = var.environment
    secret_paths      = var.vault_secret_paths
    approle_ttl       = var.approle_secret_id_ttl
  })
  
  user_data_replace_on_change = true
  
  tags = {
    Name = "${var.environment}-vault-server"
  }
  
  lifecycle {
    ignore_changes = [
      ami,  # Don't replace instance on AMI updates
    ]
  }
}

# Data source for latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EBS volume for Vault Raft storage
resource "aws_ebs_volume" "vault_data" {
  availability_zone = aws_instance.vault.availability_zone
  size              = var.vault_storage_size
  type              = "gp3"
  encrypted         = true
  kms_key_id       = aws_kms_key.vault.arn
  
  tags = {
    Name = "${var.environment}-vault-raft-storage"
  }
}

resource "aws_volume_attachment" "vault_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.vault_data.id
  instance_id = aws_instance.vault.id
  
  # Prevent Terraform from forcing detachment on destroy
  skip_destroy = true
}

# CloudWatch Log Group for Vault audit logs
resource "aws_cloudwatch_log_group" "vault_audit" {
  name              = "/aws/vault/${var.environment}/audit"
  retention_in_days = var.audit_log_retention_days
  kms_key_id       = aws_kms_key.vault.arn
  
  tags = {
    Name = "${var.environment}-vault-audit-logs"
  }
}

# Random suffix for SSM parameter uniqueness
resource "random_id" "ssm_suffix" {
  byte_length = 4
}

# SSM Parameters for storing Vault credentials (populated by user-data script)
# These are created here to set proper IAM permissions, actual values set by EC2
resource "aws_ssm_parameter" "vault_addr" {
  name        = "/${var.environment}/vault/addr"
  description = "Vault server address"
  type        = "String"
  value       = "https://${var.vault_domain}:8200"  # Initial placeholder
  
  lifecycle {
    ignore_changes = [value]  # EC2 user-data will update this
  }
  
  tags = {
    Name = "${var.environment}-vault-addr"
  }
}

resource "aws_ssm_parameter" "vault_role_id" {
  name        = "/${var.environment}/vault/role-id"
  description = "Vault AppRole Role ID"
  type        = "SecureString"
  value       = "pending-initialization-${random_id.ssm_suffix.hex}"
  key_id      = aws_kms_key.vault.id
  
  lifecycle {
    ignore_changes = [value]  # EC2 user-data will update this
  }
  
  tags = {
    Name = "${var.environment}-vault-role-id"
  }
}

resource "aws_ssm_parameter" "vault_secret_id" {
  name        = "/${var.environment}/vault/secret-id"
  description = "Vault AppRole Secret ID"
  type        = "SecureString"
  value       = "pending-initialization-${random_id.ssm_suffix.hex}"
  key_id      = aws_kms_key.vault.id
  
  lifecycle {
    ignore_changes = [value]  # EC2 user-data will update this
  }
  
  tags = {
    Name = "${var.environment}-vault-secret-id"
  }
}

resource "aws_ssm_parameter" "vault_namespace" {
  name        = "/${var.environment}/vault/namespace"
  description = "Vault namespace"
  type        = "String"
  value       = ""  # Empty for OSS Vault
  
  tags = {
    Name = "${var.environment}-vault-namespace"
  }
}

resource "aws_ssm_parameter" "vault_secret_paths" {
  name        = "/${var.environment}/vault/secret-paths"
  description = "Vault secret paths to sync"
  type        = "String"
  value       = var.vault_secret_paths
  
  tags = {
    Name = "${var.environment}-vault-secret-paths"
  }
}

# Output instructions file
resource "local_file" "deployment_instructions" {
  content = templatefile("${path.module}/templates/instructions.tpl", {
    vault_addr         = "https://${var.vault_domain}:8200"
    aws_region         = var.aws_region
    environment        = var.environment
    nameservers        = aws_route53_zone.vault.name_servers
    elastic_ip         = aws_eip.vault.public_ip
    ssm_role_id_path   = aws_ssm_parameter.vault_role_id.name
    ssm_secret_id_path = aws_ssm_parameter.vault_secret_id.name
  })
  
  filename = "${path.module}/DEPLOYMENT_COMPLETE.txt"
}
