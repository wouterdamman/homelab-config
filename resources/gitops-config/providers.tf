terraform {
  backend "s3" {
    bucket = "homelab-prd"
    key    = "tofu/gitops-config.tfstate"

    region   = "eu-central-003"
    endpoint = "https://s3.eu-central-003.backblazeb2.com"

    use_path_style = true

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
  }
}

provider "kubectl" {
  config_path = var.kube_config_path
}

provider "kubernetes" {
  config_path = var.kube_config_path
}

provider "helm" {
  kubernetes {
    config_path = var.kube_config_path
  }
}