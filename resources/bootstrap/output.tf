# tofu/output.tf
resource "local_file" "machine_configs" {
  for_each        = module.talos.machine_config
  content         = each.value.machine_configuration
  filename        = "output/talos-machine-config-${each.key}.yaml"
  file_permission = "0600"
}

resource "local_file" "talos_config" {
  content         = module.talos.client_configuration.talos_config
  filename        = "output/talos-config.yaml"
  file_permission = "0600"
}

resource "local_file" "kube_config" {
  # The server URL comes from the cluster endpoint (prd-cp-01); point it at the
  # VIP so kubectl keeps working while prd-cp-01 reboots.
  content = replace(
    module.talos.kube_config.kubeconfig_raw,
    "https://${local.cluster_config.endpoint}:6443",
    "https://${local.cluster_config.vip}:6443",
  )
  filename        = "output/kube-config.yaml"
  file_permission = "0600"
}

output "kube_config" {
  value     = module.talos.kube_config.kubeconfig_raw
  sensitive = true
}

output "talos_config" {
  value     = module.talos.client_configuration.talos_config
  sensitive = true
}
