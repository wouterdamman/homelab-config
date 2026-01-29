terraform {
  backend "s3" {
    bucket = "homelab-prd"
    key    = "tofu/bootstrap.tfstate"

    region   = "nbg1"
    endpoint = "https://nbg1.your-objectstorage.com"

    use_path_style = true

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
  }

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.93.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.8.1"
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

provider "kubernetes" {
  config_path = var.kube_config_path
}

