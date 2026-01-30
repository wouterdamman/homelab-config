# tofu/talos/image.tf
locals {
  version      = var.image.version
  schematic    = var.image.schematic
  schematic_id = jsondecode(data.http.schematic_id.response_body)["id"]
  image_id     = "${local.schematic_id}_${local.version}"

  update_version      = coalesce(var.image.update_version, var.image.version)
  update_schematic    = coalesce(var.image.update_schematic, var.image.schematic)
  update_schematic_id = jsondecode(data.http.updated_schematic_id.response_body)["id"]
  update_image_id     = "${local.update_schematic_id}_${local.update_version}"
}

data "http" "schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic
}

data "http" "updated_schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.update_schematic
}

# NOTE: Proxmox VE user-agent may be blocked by Talos Factory during initial download
# See: https://github.com/bpg/terraform-provider-proxmox/issues/1724
# Workaround: Manually pre-download new images once, then Terraform manages them
# Download: ssh root@proxmox "cd /var/lib/vz/template/iso && wget -O talos-<schematic>-<version>-nocloud-amd64.img \
#   'https://factory.talos.dev/image/<schematic>/<version>/nocloud-amd64.raw.gz'"

resource "proxmox_virtual_environment_download_file" "this" {
  for_each = toset(distinct([for k, v in var.nodes : "${v.host_node}_${v.update == true ? local.update_image_id : local.image_id}"]))

  node_name    = split("_", each.key)[0]
  content_type = "iso"
  datastore_id = var.image.proxmox_datastore

  file_name               = "talos-${split("_", each.key)[1]}-${split("_", each.key)[2]}-${var.image.platform}-${var.image.arch}.img"
  url                     = "${var.image.factory_url}/image/${split("_", each.key)[1]}/${split("_", each.key)[2]}/${var.image.platform}-${var.image.arch}.raw.gz"
  decompression_algorithm = "gz"
  overwrite               = false
  overwrite_unmanaged     = true  # Manage manually uploaded images
  verify                  = false

  # Ignore failures if image already exists manually
  lifecycle {
    ignore_changes = [url]
  }
}
