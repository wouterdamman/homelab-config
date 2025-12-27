#!/bin/bash
# Load secrets from 1Password for Terraform/OpenTofu
# Usage: source ./scripts/load-secrets.sh

# Check if being sourced (not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script must be sourced, not executed"
    echo "Usage: source ./scripts/load-secrets.sh"
    exit 1
fi

# Check if 1Password CLI is installed
if ! command -v op &> /dev/null; then
    echo "❌ Error: 1Password CLI (op) is not installed"
    echo "Install from: https://developer.1password.com/docs/cli/get-started/"
    return 1 2>/dev/null || exit 1
fi

# Check if user is signed in
if ! op whoami &> /dev/null; then
    echo "❌ Please sign in to 1Password first:"
    echo "  eval \$(op signin)"
    return 1 2>/dev/null || exit 1
fi

echo "🔐 Loading secrets from 1Password..."

# Proxmox credentials from 1Password "Homelab" vault
echo "  Loading Proxmox credentials..."
TF_VAR_proxmox_username=$(op read "op://Homelab/Proxmox/username" 2>&1 | tr -d '\n\r')
if [[ $? -ne 0 ]]; then
    echo "❌ Error loading Proxmox username: $TF_VAR_proxmox_username"
    return 1 2>/dev/null || exit 1
fi
export TF_VAR_proxmox_username

TF_VAR_proxmox_password=$(op read "op://Homelab/Proxmox/password" 2>&1 | tr -d '\n\r')
if [[ $? -ne 0 ]]; then
    echo "❌ Error loading Proxmox password: $TF_VAR_proxmox_password"
    return 1 2>/dev/null || exit 1
fi
export TF_VAR_proxmox_password

TF_VAR_proxmox_api_token=$(op read "op://Homelab/Proxmox/api_token" 2>&1 | tr -d '\n\r')
if [[ $? -ne 0 ]]; then
    echo "❌ Error loading Proxmox API token: $TF_VAR_proxmox_api_token"
    return 1 2>/dev/null || exit 1
fi
export TF_VAR_proxmox_api_token

# Backblaze B2 S3 backend from 1Password "Homelab" vault
echo "  Loading Backblaze B2 credentials..."
AWS_ACCESS_KEY_ID=$(op read "op://Homelab/Backblaze-homelab-prd/username" 2>&1 | tr -d '\n\r')
if [[ $? -ne 0 ]]; then
    echo "❌ Error loading Backblaze key ID: $AWS_ACCESS_KEY_ID"
    return 1 2>/dev/null || exit 1
fi
export AWS_ACCESS_KEY_ID

AWS_SECRET_ACCESS_KEY=$(op read "op://Homelab/Backblaze-homelab-prd/credential" 2>&1 | tr -d '\n\r')
if [[ $? -ne 0 ]]; then
    echo "❌ Error loading Backblaze secret key: $AWS_SECRET_ACCESS_KEY"
    return 1 2>/dev/null || exit 1
fi
export AWS_SECRET_ACCESS_KEY

echo "✓ Secrets loaded successfully"
echo ""
echo "Environment variables set:"
echo "  - TF_VAR_proxmox_username"
echo "  - TF_VAR_proxmox_password (hidden)"
echo "  - TF_VAR_proxmox_api_token (hidden)"
echo "  - AWS_ACCESS_KEY_ID"
echo "  - AWS_SECRET_ACCESS_KEY (hidden)"
echo ""
echo "You can now run: tofu plan, tofu apply, etc."
