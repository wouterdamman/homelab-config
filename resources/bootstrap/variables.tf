##############################
# Environment / Counts
##############################

variable "env" {
  type        = string
  description = "Environment identifier (prd or tst)"
  validation {
    condition     = contains(["prd", "tst"], var.env)
    error_message = "env must be 'prd' or 'tst'"
  }
}

variable "controlplane_count" {
  type        = number
  description = "Number of controlplane nodes"
}

variable "worker_count" {
  type        = number
  description = "Number of worker nodes"
}

variable "base_vm_id" {
  type        = number
  description = "Starting VM ID for automatic numbering"
}

variable "cluster_cidr" {
  type        = string
  description = "Cluster CIDR prefix (e.g. 10.0.10)"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){2}[0-9]{1,3}$", var.cluster_cidr))
    error_message = "cluster_cidr must be a valid IP prefix (e.g., 10.0.10)"
  }
}

variable "ip_offset" {
  type        = number
  description = "Start offset for IP addressing (e.g. 100, 200)"

  validation {
    condition     = var.ip_offset >= 1 && var.ip_offset <= 254
    error_message = "ip_offset must be between 1 and 254"
  }
}

variable "host_nodes" {
  type        = list(string)
  description = "Proxmox nodes used for placement"
}

##############################
# Proxmox access
##############################

variable "proxmox" {
  type = object({
    name         = string
    cluster_name = string
    endpoint     = string
    cluster_ip   = string
    insecure     = bool
  })
  description = "Proxmox cluster configuration (non-sensitive)"
}

variable "proxmox_api_token" {
  type        = string
  description = "Proxmox API token (e.g., automation@pve!tofu=<token>). Set via TF_VAR_proxmox_api_token"
  sensitive   = true
}

variable "kube_config_path" {
  description = "Path to kubeconfig"
  type        = string
  default     = "~/.kube/config"
}

##############################
# Talos Image
##############################

variable "talos_version" {
  type        = string
  description = "Talos version (e.g. v1.11.3)"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.talos_version))
    error_message = "Talos version must be in format vX.Y.Z (e.g., v1.12.0)"
  }
}

variable "talos_update_version" {
  type        = string
  description = "Talos upgrade target version (optional, for rolling upgrades)"
  default     = null

  validation {
    condition     = var.talos_update_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.talos_update_version))
    error_message = "Talos update version must be in format vX.Y.Z (e.g., v1.12.0) or null"
  }
}

variable "talos_schematic_path" {
  type        = string
  description = "Relative path to schematic.yaml"
}

##############################
# Cilium
##############################

variable "cilium_version" {
  type        = string
  description = "Cilium version to install (e.g., v1.18.5)"
  default     = "v1.18.5"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.cilium_version))
    error_message = "Cilium version must be in format vX.Y.Z (e.g., v1.18.5)"
  }
}

variable "cilium_install_path" {
  type        = string
  description = "Relative path to Cilium install manifest"
}

variable "cilium_values_path" {
  type        = string
  description = "Relative path to Cilium values.yaml"
}

##############################
# Gateway API
##############################

variable "gateway_api_version" {
  type        = string
  description = "Gateway API CRD version (e.g., v1.1.0, v1.2.0)"
  default     = "v1.2.0"
}

##############################
# Cluster
##############################

variable "cluster_name" {
  type        = string
  description = "Cluster name"
}

variable "cluster_gateway" {
  type        = string
  description = "Gateway for cluster network"
}

variable "proxmox_cluster" {
  type        = string
  description = "Proxmox cluster name"
}

variable "cluster_vip" {
  type        = string
  description = "Virtual IP for the control-plane Kubernetes endpoint"
}

##############################
# Node Specifications
##############################

variable "controlplane_specs" {
  type = object({
    cpu  = number
    ram  = number
    disk = number
  })
  description = "Hardware specs for control plane nodes (CPU cores, RAM in MB, disk in GB)"
  default = {
    cpu  = 4
    ram  = 8192
    disk = 250
  }
}

variable "worker_specs" {
  type = object({
    cpu            = number
    ram            = number
    disk           = number
    secondary_disk = optional(number)
  })
  description = "Hardware specs for worker nodes (CPU cores, RAM in MB, disk in GB, secondary_disk for Longhorn in GB)"
  default = {
    cpu            = 2
    ram            = 4096
    disk           = 250
    secondary_disk = 268
  }
}

##############################
# Upgrade Control
##############################

variable "nodes_to_upgrade" {
  type        = list(string)
  description = "List of node names to upgrade (e.g., ['prd-cp-01', 'prd-w-01']). Empty list means no upgrades."
  default     = []
}