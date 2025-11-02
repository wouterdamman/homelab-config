data "local_file" "secret_yaml" {
  filename = var.secret_path
}

### Step-by-Step Namespace Creation with Validation
resource "kubernetes_namespace" "namespaces" {
  for_each = toset(var.namespaces)

  metadata {
    name = each.value
  }
}

resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"

    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubectl_manifest" "apply_secrets" {
  count     = length(local.manifests)
  yaml_body = local.manifests[count.index]

  depends_on = [
    kubernetes_namespace.namespaces,
    kubernetes_namespace.longhorn_system
  ]
}

### Install 1Password Connector
resource "helm_release" "onepassword" {
  name       = "onepassword"
  repository = "https://1password.github.io/connect-helm-charts"
  chart      = "connect"
  namespace  = kubernetes_namespace.namespaces["onepassword"].metadata[0].name
  version    = var.onepassword_version
  values = [
    yamlencode({
      connect = {
        credentialsName = "onepassword-connect-credentials"
        credentialsKey  = "onepassword-connect-credentials.json"
      }
      tolerations = [
        {
          key      = "node-role.kubernetes.io/control-plane"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      ]
    })
  ]
  
  depends_on = [
    kubectl_manifest.apply_secrets
  ]
}

### Install External Secrets Operator
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = kubernetes_namespace.namespaces["external-secrets"].metadata[0].name
  version    = var.external_secrets_version
  values = [
    yamlencode({
      tolerations = [
        {
          key      = "node-role.kubernetes.io/control-plane"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

  set {
    name  = "includeCRDs"
    value = true
  }

  depends_on = [
    helm_release.onepassword
  ]
}

resource "time_sleep" "wait_for_webhook" {
  depends_on = [helm_release.external_secrets]

  create_duration = "30s" # Adjust based on readiness time
} 

# Apply ClusterSecretStore
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = file("operators/external-secrets/templates/cluster-secret-store.yaml")

  depends_on = [
    helm_release.external_secrets,
    time_sleep.wait_for_webhook
  ]
}

resource "kubectl_manifest" "github_client_secret" {
  yaml_body = file("input-files/github-client-secret.yaml")

  depends_on = [
    helm_release.external_secrets,
    time_sleep.wait_for_webhook
  ]
}

resource "kubectl_manifest" "github-private-repo-creds" {
  yaml_body = file("input-files/github-private-repo-creds.yaml")

  depends_on = [
    helm_release.external_secrets,
    time_sleep.wait_for_webhook
  ]
}

resource "kubectl_manifest" "onepassword-connect-credentials" {
  yaml_body = file("input-files/onepassword-connect-credentials.yaml")

  depends_on = [
    helm_release.onepassword,
    time_sleep.wait_for_webhook
  ]
}

# Wait for ClusterSecretStore to be ready
resource "time_sleep" "wait_for_cluster_secret_store" {
  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubectl_manifest.github_client_secret,
    kubectl_manifest.github-private-repo-creds,
    kubectl_manifest.onepassword-connect-credentials
    ]

  create_duration = "15s" # Adjust based on readiness time
}

### Install ArgoCD
resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  namespace  = kubernetes_namespace.namespaces["argocd"].metadata[0].name
  chart      = "argo-cd"
  version    = "9.0.5"
  values     = [file("./operators/argo-cd/values.yaml")]
  depends_on = [
    time_sleep.wait_for_cluster_secret_store,
    kubectl_manifest.cluster_secret_store
  ]
}

# ### Install Argo apps
resource "helm_release" "argo_helm" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  namespace  = kubernetes_namespace.namespaces["argocd"].metadata[0].name
  version    = "2.0.2"
  values = [
    yamlencode({
      projects = {
        operators = {
          namespace                = "argocd"
          displayName             = "Operators"
          finalizers              = ["resources-finalizer.argocd.argoproj.io"]
          clusterResourceWhitelist = [
            {
              group = "*"
              kind  = "*"
            }
          ]
          destinations = [
            {
              namespace = "*"
              server    = "*"
            }
          ]
          sourceRepos = ["*"]
        }
        apps = {
          namespace                = "argocd"
          displayName             = "Apps"
          finalizers              = ["resources-finalizer.argocd.argoproj.io"]
          clusterResourceWhitelist = [
            {
              group = "*"
              kind  = "*"
            }
          ]
          destinations = [
            {
              namespace = "*"
              server    = "*"
            }
          ]
          sourceRepos = ["*"]
        }
      }
    })
  ]
  depends_on = [
    helm_release.argo_cd
  ]
}


# ### Deploy Root App
resource "null_resource" "deploy_root_app" {
  provisioner "local-exec" {
    command = "helm template ./sync-app | kubectl apply -f -"
  }

  triggers = {
    argo_cd_release_id = helm_release.argo_cd.id
  }

  depends_on = [
    helm_release.argo_cd,
    helm_release.argo_helm
  ]
}

