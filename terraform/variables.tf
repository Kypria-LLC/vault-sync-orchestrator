# Terraform Variables for Production Vault Deployment
# 
# This file defines all configurable parameters for the Vault infrastructure.
# Copy terraform.tfvars.example to terraform.tfvars and customize values.

variable "aws_region" {
  description = "AWS region where Vault will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development."
  }
}

variable "vault_version" {
  description = "HashiCorp Vault version to install"
  type        = string
  default     = "1.21.1"
}

variable "vault_domain" {
  description = "Domain name for the Vault server (must be registered and configured for DNS)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*\\.[a-z]{2,}$", var.vault_domain))
    error_message = "Vault domain must be a valid domain name (e.g., vault.example.com)."
  }
}

variable "instance_type" {
  description = "EC2 instance type for Vault server"
  type        = string
  default     = "t3.medium"
  
  validation {
    condition     = can(regex("^t3\\.(small|medium|large|xlarge)", var.instance_type))
    error_message = "Instance type must be a t3 family instance (small, medium, large, xlarge)."
  }
}

variable "vault_storage_size" {
  description = "Size of EBS volume for Vault Raft storage (in GB)"
  type        = number
  default     = 50
  
  validation {
    condition     = var.vault_storage_size >= 20 && var.vault_storage_size <= 500
    error_message = "Vault storage size must be between 20 and 500 GB."
  }
}

variable "ssh_key_name" {
  description = "Name of existing EC2 SSH key pair for emergency access"
  type        = string
  
  validation {
    condition     = length(var.ssh_key_name) > 0
    error_message = "SSH key name must be provided for emergency access."
  }
}

variable "vault_secret_paths" {
  description = "Comma-separated list of secret paths to configure for GitHub Actions sync"
  type        = string
  default     = "secret/data/app1,secret/data/db-creds"
}

variable "approle_secret_id_ttl" {
  description = "TTL for AppRole Secret ID (must match 30-day rotation requirement)"
  type        = string
  default     = "720h"  # 30 days
  
  validation {
    condition     = var.approle_secret_id_ttl == "720h"
    error_message = "AppRole Secret ID TTL must be 720h (30 days) per security policy."
  }
}

variable "audit_log_retention_days" {
  description = "Number of days to retain Vault audit logs in CloudWatch"
  type        = number
  default     = 90
  
  validation {
    condition     = var.audit_log_retention_days >= 30 && var.audit_log_retention_days <= 365
    error_message = "Audit log retention must be between 30 and 365 days."
  }
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access (for emergency troubleshooting only)"
  type        = list(string)
  default     = []  # No SSH access by default
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
