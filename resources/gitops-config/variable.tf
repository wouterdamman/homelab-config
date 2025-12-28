variable "kube_config_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "secret_path" {
  description = "Path to the secret.yaml file containing 1Password Connect credentials"
  type        = string
  default     = "./input-files/secret.yaml"

  validation {
    condition     = can(regex("^.*\\.ya?ml$", var.secret_path))
    error_message = "Secret path must end with .yaml or .yml"
  }
}

variable "onepassword_version" {
  description = "1Password Connect Helm chart version"
  type        = string
  default     = "2.1.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.onepassword_version))
    error_message = "1Password version must be in format X.Y.Z (e.g., 1.17.0)"
  }
}

variable "external_secrets_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "0.20.4"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.external_secrets_version))
    error_message = "External Secrets version must be in format X.Y.Z (e.g., 0.17.0)"
  }
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "9.2.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_version))
    error_message = "ArgoCD version must be in format X.Y.Z (e.g., 9.2.2)"
  }
}

variable "argocd_apps_version" {
  description = "ArgoCD Apps Helm chart version"
  type        = string
  default     = "2.0.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_apps_version))
    error_message = "ArgoCD Apps version must be in format X.Y.Z (e.g., 2.0.2)"
  }
}

variable "namespaces" {
  description = "List of namespaces to create for GitOps bootstrap"
  type        = list(string)
  default     = ["onepassword", "external-secrets", "argocd"]
}

