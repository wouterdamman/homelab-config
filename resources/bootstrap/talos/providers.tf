# tofu/talos/providers.tf
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.105.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
