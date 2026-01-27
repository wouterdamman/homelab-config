# tofu/talos/virtual-machines.tf
resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.nodes

  node_name = each.value.host_node

  name        = each.key
  description = each.value.machine_type == "controlplane" ? "Talos Control Plane" : "Talos Worker"
  tags        = each.value.machine_type == "controlplane" ? ["k8s", "control-plane"] : ["k8s", "worker"]
  on_boot     = true
  vm_id       = each.value.vm_id

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.ram_dedicated
  }

  network_device {
    bridge      = "vmbr1"
    mac_address = each.value.mac_address
  }

  disk {
    datastore_id = each.value.datastore_id
    interface    = "scsi0"
    iothread     = false
    cache        = "none"
    discard      = "on"
    ssd          = false
    file_format  = "raw"
    size         = each.value.disk_size
    file_id      = proxmox_virtual_environment_download_file.this["${each.value.host_node}_${each.value.update == true ? local.update_image_id : local.image_id}"].id
  }

  # Secondary disk for Longhorn storage (workers only)
  dynamic "disk" {
    for_each = each.value.secondary_disk_size != null ? [1] : []
    content {
      datastore_id = "storage"
      interface    = "scsi1"
      iothread     = false
      cache        = "none"
      discard      = "on"
      ssd          = false
      file_format  = "raw"
      size         = each.value.secondary_disk_size
    }
  }

  boot_order = ["scsi0"]

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 6.X.
  }

  lifecycle {
    ignore_changes = [
      disk[0].file_id, # Cannot be determined during import
      initialization,  # Already initialized, avoid recreation
      vga,             # Computed field
    ]
  }

  initialization {
    datastore_id = each.value.datastore_id

    dns {
      servers = [var.cluster.gateway]
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/25"
        gateway = var.cluster.gateway
      }
    }
  }

  dynamic "hostpci" {
    for_each = each.value.igpu ? [1] : []
    content {
      # Passthrough iGPU
      device  = "hostpci0"
      mapping = "iGPU"
      pcie    = true
      rombar  = true
      xvga    = false
    }
  }
}
