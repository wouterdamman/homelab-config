# tofu/providers.tf
terraform {
  backend "local" {
    path = "/Users/wouter/personal/homelab-config/resources/state/talos.tfstate"  # Local path for the state file
  }

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.9.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.86.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox.endpoint
  username = var.proxmox.username
  password = var.proxmox.password
  insecure = var.proxmox.insecure
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

