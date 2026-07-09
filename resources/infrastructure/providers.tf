terraform {
  backend "s3" {
    bucket = "homelab-prd"
    key    = "tofu/infrastructure.tfstate"

    region   = "nbg1"
    endpoint = "https://nbg1.your-objectstorage.com"

    use_path_style = true

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox.endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox.insecure

  ssh {
    agent = true

    node {
      name    = var.proxmox.name
      address = var.proxmox.cluster_ip
    }
  }
}
