# ArgoCD Configuration

**Source:** `resources/gitops-config/operators/argo-cd/values.yaml`

---

## Overview

ArgoCD is the GitOps continuous deployment tool managing all Kubernetes resources via the App-of-Apps pattern. Configured with GitHub SSO, Prometheus monitoring, and prepared for Slack notifications.

---

## Architecture

```
sync-app (Root Application) — App-of-Apps Pattern
├── Wave 0 (tier-0): ArgoCD, Cilium, Longhorn
├── Wave 1 (tier-0/1): sync-app, 1Password, External Secrets, cert-manager,
│                      external-dns, kubelet-csr-approver, cloudnative-pg
├── Wave 2 (tier-2): Prometheus, Grafana, Loki, Promtail, Authentik, PVE Exporter
├── Wave 3 (tier-2): Proxmox Gateway API
└── Wave 4 (tier-3): Applications (EMQX, Zigbee2MQTT, Home Assistant, etc.)
```

---

## Authentication — GitHub SSO (Dex)

Local admin login is disabled. Authentication via GitHub OAuth through Dex.

| Setting | Value |
|---------|-------|
| Provider | GitHub OAuth (via Dex connector) |
| Organization | sironite |
| Admin Group | sironite:Owners |
| Default Role | role:readonly |
| Local Admin | Disabled (`admin.enabled: false`) |

```yaml
configs:
  rbac:
    policy.csv: |
      g, sironite:Owners, role:admin
      g, sironite:sironite, role:admin
      g, wouterdamman, role:admin
    policy.default: role:readonly
    scopes: "[groups, preferred_username]"
```

**Secret:** `argocd/github-client-secret` — 1Password item `github-client-secrets` (KubernetesSecrets vault)

---

## Access

| Service | URL | Authentication |
|---------|-----|----------------|
| ArgoCD UI | https://argocd.svc.damman.tech | GitHub SSO |

TLS terminated at Cilium Gateway. ArgoCD server runs in insecure mode:
```yaml
configs:
  params:
    server.insecure: true
```

---

## Performance Tuning

| Parameter | Value | Purpose |
|-----------|-------|---------|
| controller.status.processors | 20 | Parallel status updates |
| controller.operation.processors | 10 | Parallel sync operations |
| controller.self.heal.timeout.seconds | 5 | Faster self-heal response |
| reposerver.parallelism.limit | 0 (unlimited) | No limit on repo operations |

---

## Resource Configuration

All components run on control-plane nodes.

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| Controller | 100m | 1500m | 512Mi | 1536Mi |
| Server | 2m | 250m | 64Mi | 128Mi |
| Repo Server | 100m | 1000m | 256Mi | 512Mi |
| Redis | 5m | 100m | 32Mi | 128Mi |
| Dex | 5m | 100m | 128Mi | 256Mi |
| ApplicationSet | 10m | 500m | 64Mi | 128Mi |
| Notifications | 1m | 100m | 32Mi | 64Mi |

---

## Monitoring

ServiceMonitors enabled for all ArgoCD components (label: `release: prometheus`).

**Key metrics:**
- `argocd_app_info` — Application status and health
- `argocd_app_sync_total` — Sync operations count
- `argocd_cluster_api_resource_objects` — Tracked resources
- `argocd_git_request_total` — Git operations

---

## Resource Exclusions

High-churn resources excluded from tracking to prevent unnecessary syncs:

```yaml
configs:
  cm:
    resource.exclusions: |
      - apiGroups: ['cilium.io']
        kinds: ['CiliumIdentity']
        clusters: ['*']
```

---

## Notifications (Prepared — not yet active)

Slack notifications are prepared but not yet enabled. See ADR-014.

| Trigger | Condition | Template |
|---------|-----------|---------|
| on-deployed | Sync succeeded + Healthy | app-deployed |
| on-health-degraded | Health == Degraded | app-health-degraded |
| on-sync-failed | Phase in [Error, Failed] | app-sync-failed |

**Activation steps:**
1. Create Slack channel `#homelab-alerts` with webhook token
2. Add token to 1Password
3. Create ExternalSecret `argocd-notifications-secret`
4. Uncomment config and set `notifications.enabled: true`

---

## Troubleshooting

```bash
# Application status
kubectl get applications -n argocd
argocd app list

# Sync errors
argocd app get <app-name>
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Force sync
argocd app sync <app-name> --force

# Check Dex (SSO) logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-dex-server
```
