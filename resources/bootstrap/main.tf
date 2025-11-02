# tofu/main.tf
module "talos" {
  source = "./talos"

  providers = {
    proxmox = proxmox
  }

  image = {
    version   = "v1.11.3"
    schematic = file("${path.module}/talos/image/schematic.yaml")
  }

  cilium = {
    install = file("${path.module}/talos/inline-manifests/cilium-install.yaml")
    values = file(abspath("${path.module}/../gitops-config/operators/cilium/values.yaml"))
    # values  = file("${path.module}/talos/inline-manifests/values.yaml")
  }

  cluster = {
    name            = "talos"
    endpoint        = "10.0.10.210"
    gateway         = "10.0.10.193"
    talos_version   = "v1.11"
    proxmox_cluster = "homelab"
  }

  nodes = { #(Kube Nodes: 10.0.10.210-220 | Kube API: 10.0.10.230 | Cilium-pool: 10.0.0.240-250)
    "ctrl-00" = {
      host_node     = "dmn-sk-pve-01"
      machine_type  = "controlplane"
      ip            = "10.0.10.210"
      mac_address   = "BC:24:11:2E:C8:00"
      vm_id         = 800
      cpu           = 2
      ram_dedicated = 4096
      disk_size     = 100
    }
    "ctrl-01" = {
      host_node     = "dmn-sk-pve-01"
      machine_type  = "controlplane"
      ip            = "10.0.10.211"
      mac_address   = "BC:24:11:2E:C8:01"
      vm_id         = 801
      cpu           = 2
      ram_dedicated = 4096
      disk_size     = 100
    }
    "ctrl-02" = {
      host_node     = "dmn-sk-pve-02"
      machine_type  = "controlplane"
      ip            = "10.0.10.212"
      mac_address   = "BC:24:11:2E:C8:02"
      vm_id         = 802
      cpu           = 2
      ram_dedicated = 4096
      disk_size     = 100
    }
    "work-00" = {
      host_node     = "dmn-sk-pve-01"
      machine_type  = "worker"
      ip            = "10.0.10.213"
      mac_address   = "BC:24:11:2E:08:00"
      vm_id         = 810
      cpu           = 2
      ram_dedicated = 4096
      disk_size     = 250
    }
    "work-01" = {
      host_node     = "dmn-sk-pve-01"
      machine_type  = "worker"
      ip            = "10.0.10.214"
      mac_address   = "BC:24:11:2E:08:01"
      vm_id         = 811
      cpu           = 4
      ram_dedicated = 8192
      disk_size     = 250
    }
    "work-02" = {
      host_node     = "dmn-sk-pve-01"
      machine_type  = "worker"
      ip            = "10.0.10.215"
      mac_address   = "BC:24:11:2E:08:02"
      vm_id         = 812
      cpu           = 4
      ram_dedicated = 8192
      disk_size     = 250
    }
    "work-03" = {
      host_node     = "dmn-sk-pve-01"
      machine_type  = "worker"
      ip            = "10.0.10.216"
      mac_address   = "BC:24:11:2E:08:03"
      vm_id         = 813
      cpu           = 4
      ram_dedicated = 8192
      disk_size     = 250
    }
    "work-04" = {
      host_node     = "dmn-sk-pve-02"
      machine_type  = "worker"
      ip            = "10.0.10.217"
      mac_address   = "BC:24:11:2E:08:04"
      vm_id         = 814
      cpu           = 2
      ram_dedicated = 4096
      disk_size     = 250
    }
  }
}

# module "proxmox_csi_plugin" {
#   depends_on = [module.talos]
#   source = "./proxmox-csi-plugin"

#   providers = {
#     proxmox    = proxmox
#     kubernetes = kubernetes
#   }

#   proxmox = var.proxmox
# }
