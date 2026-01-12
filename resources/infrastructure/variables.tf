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

##############################
# Cluster Configuration
##############################

variable "cluster_cidr" {
  type        = string
  description = "Cluster CIDR prefix (e.g. 10.0.10)"
}

variable "cluster_gateway" {
  type        = string
  description = "Gateway for cluster network"
}

variable "host_nodes" {
  type        = list(string)
  description = "Proxmox nodes used for placement"
}

variable "qdevice_root_password" {
  type        = string
  description = "Root password for QDevice LXC container. Set via TF_VAR_qdevice_root_password"
  sensitive   = true
}

