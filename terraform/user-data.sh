#!/bin/bash
# Vault EC2 Instance Initialization Script
# This script runs on first boot to install and configure Vault

set -e
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Vault installation"

# Install dependencies
apt-get update
apt-get install -y wget unzip certbot python3-certbot-dns-route53 awscli

# Install Vault
VAULT_VERSION="${vault_version}"
wget https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_linux_amd64.zip
unzip vault_${vault_version}_linux_amd64.zip
mv vault /usr/local/bin/
chmod +x /usr/local/bin/vault

# Create Vault user and directories
useradd --system --home /etc/vault.d --shell /bin/false vault
mkdir -p /opt/vault/data /etc/vault.d
chown -R vault:vault /opt/vault /etc/vault.d

# Configure TLS with Let's Encrypt
certbot certonly --dns-route53 -d ${vault_domain} --non-interactive --agree-tos -m admin@${vault_domain}

# Create Vault configuration
cat > /etc/vault.d/vault.hcl <<EOF
storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-node-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_cert_file = "/etc/letsencrypt/live/${vault_domain}/fullchain.pem"
  tls_key_file  = "/etc/letsencrypt/live/${vault_domain}/privkey.pem"
}

api_addr = "https://${vault_domain}:8200"
cluster_addr = "https://${vault_domain}:8201"
ui = true
EOF

# Create systemd service
cat > /etc/systemd/system/vault.service <<EOF
[Unit]
Description=HashiCorp Vault
After=network.target

[Service]
User=vault
Group=vault
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vault
systemctl start vault

# Wait for Vault to start
sleep 10

# Initialize Vault
export VAULT_ADDR="https://${vault_domain}:8200"
vault operator init -key-shares=1 -key-threshold=1 -format=json > /root/vault-init.json

# Extract unseal key and root token
UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' /root/vault-init.json)
ROOT_TOKEN=$(jq -r '.root_token' /root/vault-init.json)

# Unseal Vault
vault operator unseal \$UNSEAL_KEY

# Login with root token
vault login \$ROOT_TOKEN

# Enable AppRole auth
vault auth enable approle

# Create policy for GitHub Actions
vault policy write github-actions-policy - <<EOF
path "${secret_paths}" {
  capabilities = ["read", "list"]
}
EOF

# Create AppRole
vault write auth/approle/role/github-actions-sync \\
  secret_id_ttl=${approle_ttl} \\
  token_ttl=10m \\
  token_max_ttl=15m \\
  policies="github-actions-policy"

# Generate Role ID and Secret ID
ROLE_ID=$(vault read -field=role_id auth/approle/role/github-actions-sync/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/github-actions-sync/secret-id)

# Store credentials in AWS SSM
aws ssm put-parameter --name "/${environment}/vault/addr" --value "https://${vault_domain}:8200" --type String --overwrite --region ${aws_region}
aws ssm put-parameter --name "/${environment}/vault/role-id" --value "\$ROLE_ID" --type SecureString --overwrite --region ${aws_region}
aws ssm put-parameter --name "/${environment}/vault/secret-id" --value "\$SECRET_ID" --type SecureString --overwrite --region ${aws_region}

echo "Vault installation and configuration complete"
