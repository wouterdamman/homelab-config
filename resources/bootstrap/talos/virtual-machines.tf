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
    # cgroup v2 cpu.weight (default 100). pve-01 has 6 cores / 12 threads for
    # 15 vCPUs. Normal load is ~4 cores, but during reboots and Longhorn
    # rebuilds the workers peak at 3 cores each and etcd misses heartbeats.
    # Give the control planes 4x the weight so etcd and the apiserver win
    # under contention; idle CPU is still shared freely.
    units = each.value.machine_type == "controlplane" ? 400 : 100
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
    iothread     = true
    cache        = "none"
    discard      = "on"
    ssd          = false
    file_format  = "raw"
    size         = each.value.disk_size
    file_id      = null # Managed manually, ignored in lifecycle
  }

  # Secondary disk for Longhorn storage (workers only)
  dynamic "disk" {
    for_each = each.value.secondary_disk_size != null ? [1] : []
    content {
      datastore_id = "storage"
      interface    = "scsi1"
      iothread     = true
      cache        = "none"
      discard      = "on"
      ssd          = false
      file_format  = "raw"
      size         = each.value.secondary_disk_size
    }
  }

  # Serial console (socket), e.g. for `qm terminal`. Per node, because adding
  # or removing the device needs a VM restart.
  dynamic "serial_device" {
    for_each = each.value.serial_console ? [1] : []
    content {
      device = "socket"
    }
  }

  boot_order = ["scsi0"]

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 6.X.
  }

  # Stage hardware changes (RAM, iothread) instead of letting the provider
  # reboot VMs on apply. Roll them out node by node with a drain and a power
  # cycle; see docs/operations/talos-upgrade.md.
  reboot_after_update = false

  lifecycle {
    ignore_changes = [
      disk[0].file_id, # Manually managed, see image.tf
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
