############################################################
# MAC GENERATOR
############################################################

locals {
  mac_prefix = "BC:24:11"

  mac = {
    for idx in range(var.controlplane_count + var.worker_count) :
    idx => format(
      "%s:%s:%s:%s",
      local.mac_prefix,
      substr(random_id.mac_bytes[idx].hex, 0, 2),
      substr(random_id.mac_bytes[idx].hex, 2, 2),
      substr(random_id.mac_bytes[idx].hex, 4, 2)
    )
  }
}

############################################################
# NODE GROUPS
############################################################

locals {
  controlplanes = {
    for i in range(var.controlplane_count) :
    format("%s-cp-%02d", var.env, i + 1) => {
      index        = i
      machine_type = "controlplane"
    }
  }

  workers = {
    for i in range(var.worker_count) :
    format("%s-w-%02d", var.env, i + 1) => {
      index        = var.controlplane_count + i
      machine_type = "worker"
    }
  }

  generated_nodes = merge(local.controlplanes, local.workers)
}

############################################################
# FINAL NODE MAP
############################################################

locals {
  nodes = {
    for name, cfg in local.generated_nodes :
    name => {
      vm_id        = var.base_vm_id + cfg.index
      ip           = format("%s.%d", var.cluster_cidr, var.ip_offset + cfg.index)
      mac_address  = local.mac[cfg.index]
      machine_type = cfg.machine_type
      host_node    = var.host_nodes[cfg.index % length(var.host_nodes)]

      cpu           = cfg.machine_type == "controlplane" ? var.controlplane_specs.cpu : var.worker_specs.cpu
      ram_dedicated = cfg.machine_type == "controlplane" ? var.controlplane_specs.ram : var.worker_specs.ram
      disk_size     = cfg.machine_type == "controlplane" ? var.controlplane_specs.disk : var.worker_specs.disk

      # Mark node for upgrade if it's in the upgrade list
      update = contains(var.nodes_to_upgrade, name)

      hostname = format(
        "%s-%s-%02d",
        var.env,
        cfg.machine_type == "controlplane" ? "cp" : "w",
        cfg.index + 1
      )
    }
  }
}

############################################################
# TALOS IMAGE CONFIG
############################################################

locals {
  # Validate file paths exist before processing
  _talos_schematic_check = fileexists(abspath("${path.module}/${var.talos_schematic_path}")) ? true : tobool("ERROR: talos_schematic_path file not found: ${var.talos_schematic_path}")

  image_config = {
    version        = var.talos_version
    update_version = var.talos_update_version
    schematic      = file(abspath("${path.module}/${var.talos_schematic_path}"))
  }
}

############################################################
# CILIUM CONFIG
############################################################

locals {
  # Validate file paths exist before processing
  _cilium_install_check = fileexists(abspath("${path.module}/${var.cilium_install_path}")) ? true : tobool("ERROR: cilium_install_path file not found: ${var.cilium_install_path}")
  _cilium_values_check  = fileexists(abspath("${path.module}/${var.cilium_values_path}")) ? true : tobool("ERROR: cilium_values_path file not found: ${var.cilium_values_path}")

  cilium_config = {
    install = templatefile(abspath("${path.module}/${var.cilium_install_path}"), {
      cilium_version = var.cilium_version
    })
    values  = file(abspath("${path.module}/${var.cilium_values_path}"))
    version = var.cilium_version
  }
}

############################################################
# CLUSTER CONFIG (AUTO ENDPOINT)
############################################################

locals {
  cluster_config = {
    name               = var.cluster_name
    endpoint           = format("%s.%d", var.cluster_cidr, var.ip_offset)
    gateway            = var.cluster_gateway
    talos_version      = substr(var.talos_version, 0, 5)
    proxmox_cluster    = var.proxmox_cluster
    vip                = var.cluster_vip
    gateway_api_version = var.gateway_api_version
  }
}
