resource "random_id" "mac_bytes" {
  for_each = {
    for idx in range(var.controlplane_count + var.worker_count) :
    idx => idx
  }

  byte_length = 3
}

module "talos" {
  source = "./talos"

  providers = {
    proxmox = proxmox
  }

  nodes   = local.nodes
  image   = local.image_config
  cilium  = local.cilium_config
  cluster = local.cluster_config
}
