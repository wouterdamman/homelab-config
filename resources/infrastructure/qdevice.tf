##############################################
# QDEVICE LXC CONTAINER
##############################################
# QDevice provides external vote for 2-node cluster quorum
# Deployed as LXC container on Proxmox for minimal footprint

resource "proxmox_virtual_environment_container" "qdevice" {
  node_name = var.host_nodes[0] # Deploy on first node (dmn-sk-pve-01)
  vm_id     = 200

  description = "QDevice for Proxmox cluster quorum - External vote arbiter"

  operating_system {
    type             = "debian"
    template_file_id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512 # 512MB RAM
  }

  disk {
    datastore_id = "local"
    size         = 2 # 2GB disk
  }

  network_interface {
    name = "eth0"
  }

  started      = true
  unprivileged = true

  startup {
    order = 1
  }

  initialization {
    hostname = "qdevice-primary"

    user_account {
      password = var.qdevice_root_password
    }

    dns {
      servers = [
        "${var.cluster_cidr}.1", # UniFi Gateway
        "1.1.1.1"                 # Cloudflare
      ]
    }

    ip_config {
      ipv4 {
        address = "${var.cluster_cidr}.202/24"
        gateway = var.cluster_gateway
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Output voor verificatie
output "qdevice_ip" {
  value       = "${var.cluster_cidr}.202"
  description = "QDevice LXC IP address"
}
