##############################################
# PROXMOX ROLES
##############################################
# Custom roles that were created by hand with pveum. ACLs (who gets which role
# on which path) are not managed here yet.

# automation@pve (OpenTofu token): VMs, disks and storage for the Talos cluster.
resource "proxmox_virtual_environment_role" "automation" {
  role_id = "AutomationRole"

  privileges = [
    "Datastore.Allocate",
    "Datastore.AllocateSpace",
    "Datastore.AllocateTemplate",
    "Datastore.Audit",
    "Pool.Allocate",
    "VM.Allocate",
    "VM.Audit",
    "VM.Config.CDROM",
    "VM.Config.CPU",
    "VM.Config.Disk",
    "VM.Config.HWType",
    "VM.Config.Memory",
    "VM.Config.Network",
    "VM.Config.Options",
    "VM.Console",
    # PVE 9 split the guest agent privileges out of VM.Audit; the bpg provider
    # reads VM network interfaces through the agent.
    "VM.GuestAgent.Audit",
    "VM.PowerMgmt",
    "VM.Snapshot",
  ]
}

# automation@pve on /vms: clone and migrate on top of AutomationRole.
resource "proxmox_virtual_environment_role" "terraform_vm" {
  role_id = "TerraformVMRole"

  privileges = [
    "VM.Allocate",
    "VM.Audit",
    "VM.Clone",
    "VM.Config.CDROM",
    "VM.Config.CPU",
    "VM.Config.Disk",
    "VM.Config.HWType",
    "VM.Config.Memory",
    "VM.Config.Network",
    "VM.Config.Options",
    "VM.Migrate",
    "VM.PowerMgmt",
  ]
}

# monitoring@pve: read-only access for prometheus-pve-exporter.
resource "proxmox_virtual_environment_role" "monitoring" {
  role_id = "MonitoringRole"

  privileges = [
    "Datastore.Audit",
    "Sys.Audit",
    "VM.Audit",
  ]
}

import {
  to = proxmox_virtual_environment_role.automation
  id = "AutomationRole"
}

import {
  to = proxmox_virtual_environment_role.terraform_vm
  id = "TerraformVMRole"
}

import {
  to = proxmox_virtual_environment_role.monitoring
  id = "MonitoringRole"
}
