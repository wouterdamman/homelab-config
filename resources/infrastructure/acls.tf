##############################################
# PROXMOX ACLS
##############################################
# Role assignments per path, imported as they existed on 2026-10-26. All use
# propagate = true, so the per-VM AutomationRole entries are redundant with
# the one on /vms; they are kept to match the live state.

locals {
  acls = {
    # Human admin (SSO via Authentik)
    "wouter-root-admin" = { user = "wouter@authentik", path = "/", role = "Administrator" }

    # OpenTofu token. PVEAdmin on / gives near-full admin rights and makes the
    # custom roles mostly redundant; remove it together with the token rotation.
    "automation-root-pveadmin"   = { user = "automation@pve", path = "/", role = "PVEAdmin" }
    "automation-root"            = { user = "automation@pve", path = "/", role = "AutomationRole" }
    "automation-storage-local"   = { user = "automation@pve", path = "/storage/local", role = "AutomationRole" }
    "automation-storage-locallv" = { user = "automation@pve", path = "/storage/local-lvm", role = "AutomationRole" }
    "automation-vms"             = { user = "automation@pve", path = "/vms", role = "AutomationRole" }
    "automation-vms-terraform"   = { user = "automation@pve", path = "/vms", role = "TerraformVMRole" }
    "automation-vm-501"          = { user = "automation@pve", path = "/vms/501", role = "AutomationRole" }
    "automation-vm-502"          = { user = "automation@pve", path = "/vms/502", role = "AutomationRole" }
    "automation-vm-503"          = { user = "automation@pve", path = "/vms/503", role = "AutomationRole" }
    "automation-vm-504"          = { user = "automation@pve", path = "/vms/504", role = "AutomationRole" }
    "automation-vm-505"          = { user = "automation@pve", path = "/vms/505", role = "AutomationRole" }

    # prometheus-pve-exporter
    "monitoring-root"         = { user = "monitoring@pve", path = "/", role = "MonitoringRole" }
    "monitoring-root-auditor" = { user = "monitoring@pve", path = "/", role = "PVEAuditor" }
  }
}

resource "proxmox_acl" "this" {
  for_each = local.acls

  user_id   = each.value.user
  path      = each.value.path
  role_id   = each.value.role
  propagate = true

  lifecycle {
    # Losing the admin or automation ACL locks out the operator or this
    # workspace itself; removing one must be a deliberate code change.
    prevent_destroy = true
  }
}

import {
  for_each = local.acls
  to       = proxmox_acl.this[each.key]
  id       = "${each.value.path}?${each.value.user}?${each.value.role}"
}
