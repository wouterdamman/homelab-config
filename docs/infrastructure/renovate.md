# Renovate Configuration

Renovate is used to automatically track and update dependency versions across the homelab configuration repository. It scans ArgoCD Application manifests for Helm chart versions, Docker image tags in Helm values files, and Terraform provider versions, then opens pull requests when newer versions are available.

Repository: [TheIronRock95/homelab-config](https://github.com/TheIronRock95/homelab-config)
Configuration file: `renovate.json` in the repository root.

---

## Scanned File Types

| Manager | File pattern | What it tracks |
|---------|-------------|----------------|
| ArgoCD | `resources/gitops-config/sync-app/templates/*.yaml` | Helm chart versions (`targetRevision`) |
| Helm Values | `resources/gitops-config/applications/**/values.yaml` | Docker image tags in Helm values files |
| Terraform | All `.tf` files | Provider versions in `required_providers` |

---

## Update Schedule

Renovate runs and opens PRs **every Monday before 06:00 UTC**. This prevents PR noise throughout the week and bundles updates into a single review moment.

---

## PR Title Format

All PRs follow this naming convention:

```
[Tier: X] [updateType] chore(deps): update <package> to <version>
```

Examples:
- `[Tier: 0] [minor] chore(deps): update helm release argo-cd to v9.5.0`
- `[Tier: 1] [patch] chore(deps): update helm release cert-manager to v1.19.4`
- `[Tier: 2+] [patch] chore(deps): update helm charts (tier-2+) - patches`
- `[Tier: Infra] [minor] chore(deps): update terraform proxmox to v0.97.1`

---

## Package Rules

### Tier system

All ArgoCD applications have a tier label (`homelab.damman.tech/tier`) that reflects their criticality. This tier determines how Renovate handles updates.

| Tier | Applications | Patch | Minor | Major |
|------|-------------|-------|-------|-------|
| Tier-0 | argo-cd, argocd-apps, cilium, longhorn | Own PR, manual merge | Own PR, manual merge | Own PR, manual merge |
| Tier-1 | cert-manager, cloudnative-pg, external-dns, external-secrets, kubelet-csr-approver, onepassword-connect | Own PR, manual merge | Own PR, manual merge | Own PR, manual merge |
| Tier-2+ | authentik, loki, kube-prometheus-stack, promtail, evcc, home-assistant, zigbee2mqtt | Grouped PR, **automerge** | Own PR, manual merge | Own PR, manual merge |
| Terraform | All providers (proxmox, kubernetes, helm, …) | Grouped PR, manual merge | Grouped PR, manual merge | Grouped PR, manual merge |

### kube-prometheus-stack exception

> ⚠️ `kube-prometheus-stack` releases patch versions very frequently (often daily). Patch updates are **disabled** for this chart — only **minor** and **major** updates will open a PR.

### Ignored packages
- `emqx/emqx` docker image — ignored entirely (managed manually)

---

## Current renovate.json

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],

  "argocd": {
    "fileMatch": [
      "resources/gitops-config/sync-app/templates/.*\\.yaml"
    ]
  },

  "schedule": ["before 6am on Monday"],

  "prTitle": "{{{commitMessagePrefix}}} [{{updateType}}] chore(deps): {{{commitMessageAction}}} {{{commitMessageTopic}}}{{{commitMessageExtra}}}",

  "customManagers": [
    {
      "description": "Track hardcoded utility images in Helm template files",
      "customType": "regex",
      "fileMatch": ["resources/gitops-config/.*/templates/.*\\.yaml"],
      "matchStrings": ["image: (?<depName>busybox|redis|alpine/k8s|ghcr\\.io/coder/code-server):(?<currentValue>[^\\s\"]+)"],
      "datasourceTemplate": "docker"
    }
  ],

  "packageRules": [
    {
      "description": "Add [Tier: 0] prefix to tier-0 PR titles",
      "matchManagers": ["argocd"],
      "matchPackageNames": ["argo-cd", "argocd-apps", "cilium", "longhorn"],
      "commitMessagePrefix": "[Tier: 0]"
    },
    {
      "description": "Add [Tier: 1] prefix to tier-1 PR titles",
      "matchManagers": ["argocd"],
      "matchPackageNames": [
        "cert-manager", "cloudnative-pg", "external-dns",
        "external-secrets", "kubelet-csr-approver", "connect"
      ],
      "commitMessagePrefix": "[Tier: 1]"
    },
    {
      "description": "Group tier-2+ patch updates into a single automerged PR",
      "matchManagers": ["argocd", "helm-values"],
      "matchUpdateTypes": ["patch"],
      "excludePackageNames": [
        "argo-cd", "argocd-apps", "cilium", "longhorn",
        "cert-manager", "cloudnative-pg", "external-dns",
        "external-secrets", "kubelet-csr-approver", "connect",
        "kube-prometheus-stack"
      ],
      "groupName": "Helm charts (tier-2+) - patches",
      "commitMessagePrefix": "[Tier: 2+]",
      "automerge": true
    },
    {
      "description": "Individual PRs for tier-2+ minor and major updates",
      "matchManagers": ["argocd", "helm-values"],
      "matchUpdateTypes": ["minor", "major"],
      "excludePackageNames": [
        "argo-cd", "argocd-apps", "cilium", "longhorn",
        "cert-manager", "cloudnative-pg", "external-dns",
        "external-secrets", "kubelet-csr-approver", "connect"
      ],
      "commitMessagePrefix": "[Tier: 2+]"
    },
    {
      "description": "Ignore emqx/emqx docker image updates",
      "matchPackageNames": ["emqx/emqx"],
      "enabled": false
    },
    {
      "description": "Disable patch updates for kube-prometheus-stack",
      "matchPackageNames": ["kube-prometheus-stack"],
      "matchUpdateTypes": ["patch"],
      "enabled": false
    },
    {
      "description": "Group all Terraform provider updates",
      "matchManagers": ["terraform"],
      "groupName": "Terraform providers",
      "commitMessagePrefix": "[Tier: Infra]"
    }
  ]
}
```
