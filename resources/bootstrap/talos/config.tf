# tofu/talos/talos-config.tf
resource "talos_machine_secrets" "this" {
  talos_version = var.cluster.talos_version

  # The secrets bundle (CAs, cluster ID, tokens) is generated once at bootstrap.
  # With provider 0.12 a talos_version bump re-plans every cert and key as
  # "known after apply", which would rotate the whole PKI on a live cluster.
  lifecycle {
    ignore_changes = [talos_version]
  }
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.nodes : v.ip]
  endpoints            = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"]
}

data "talos_machine_configuration" "this" {
  for_each         = var.nodes
  cluster_name     = var.cluster.name
  cluster_endpoint = "https://${var.cluster.endpoint}:6443"
  talos_version    = local.config_contract
  machine_type     = each.value.machine_type
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = each.value.machine_type == "controlplane" ? [
    templatefile("${path.module}/machine-config/control-plane.yaml.tftpl", {
      hostname            = each.key
      node_name           = each.value.host_node
      cluster_name        = var.cluster.proxmox_cluster
      cilium_values       = var.cilium.values
      cilium_install      = var.cilium.install
      cilium_version      = var.cilium.version
      gateway_api_version = var.cluster.gateway_api_version
      vip                 = var.cluster.vip
      gateway             = var.cluster.gateway
      ip                  = each.value.ip
      cidr                = 25
    })
    ] : concat([
      templatefile("${path.module}/machine-config/worker.yaml.tftpl", {
        hostname     = each.key
        node_name    = each.value.host_node
        cluster_name = var.cluster.proxmox_cluster
        gateway      = var.cluster.gateway
        ip           = each.value.ip
        cidr         = 25
      })
    ],
    # Talos 1.14 workload isolation (CRI, kubelet and pods in the sandboxd
    # namespace). Rolled out per node; takes effect after a reboot.
    contains(local.workload_isolation_nodes, each.key) ? [yamlencode({
      apiVersion        = "v1alpha1"
      kind              = "SecurityProfileConfig"
      workloadIsolation = true
    })] : [],
  )
}

locals {
  # Machine config contract, kept at the version the patches are written for.
  # With contract v1.14 the provider generates KubeNetworkConfig, KubeProxyConfig
  # and other new documents, and nodes reject them next to the v1alpha1 fields
  # our templates set (.cluster.network, .machine.kubelet, ...). Talos 1.14 nodes
  # accept v1.13-contract configs; bump this only after migrating the templates.
  config_contract = "v1.13"

  # Validated on prd-w-01 on 2026-10-26: Longhorn iSCSI attach/detach and
  # replica rebuild work under isolation.
  workload_isolation_nodes = ["prd-w-01"]
}

resource "talos_machine_configuration_apply" "this" {
  depends_on                  = [proxmox_virtual_environment_vm.this]
  for_each                    = var.nodes
  node                        = each.value.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  lifecycle {
    # re-run config apply if vm changes
    replace_triggered_by = [proxmox_virtual_environment_vm.this[each.key]]
  }
}

resource "talos_machine_bootstrap" "this" {
  node                 = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"][0]
  endpoint             = var.cluster.endpoint
  client_configuration = talos_machine_secrets.this.client_configuration
}

data "talos_cluster_health" "this" {
  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.this
  ]
  client_configuration = data.talos_client_configuration.this.client_configuration
  control_plane_nodes  = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"]
  worker_nodes         = [for k, v in var.nodes : v.ip if v.machine_type == "worker"]
  endpoints            = data.talos_client_configuration.this.endpoints
  timeouts = {
    read = "10m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this,
    data.talos_cluster_health.this
  ]

  node = [
    for k, v in var.nodes :
    v.ip if v.machine_type == "controlplane"
  ][0]

  # Talos API endpoint used to fetch the kubeconfig; the VIP survives a
  # prd-cp-01 reboot. The server URL inside is rewritten in output.tf.
  endpoint             = var.cluster.vip
  client_configuration = talos_machine_secrets.this.client_configuration

  timeouts = {
    read = "1m"
  }
}

