# Architecture Decision Records (ADR)

Documentation of important architecture decisions for the homelab infrastructure. Each ADR records what was decided, why, and which alternatives were considered.

**Principle:** ADRs are short and concise. For detailed technical information, see the linked configuration pages.

---

## ADR-001: Talos Linux as Kubernetes OS

**Status:** Accepted
**Date:** 2025-12-20

### Decision
**Talos Linux** as the Kubernetes-specific operating system.

### Why?
- **Security:** Immutable OS, no SSH, minimal attack surface
- **Kubernetes-native:** API-driven, declarative configuration
- **Maintenance:** Automatic rolling updates, no OS patching
- **Production-grade:** Used by enterprises, battle-tested

### Alternatives
- ❌ **k3s on Ubuntu** — More maintenance, security patching, SSH attack surface
- ❌ **Flatcar Container Linux** — Less Kubernetes-specific
- ❌ **RKE2 on Rocky Linux** — Too heavy for homelab

### Trade-offs
- ✅ No security patching needed
- ✅ Declarative infrastructure
- ❌ Debugging harder (no shell)
- ❌ Steep learning curve

---

## ADR-002: Cilium as CNI

**Status:** Accepted
**Date:** 2025-12-21

### Decision
**Cilium** as Container Network Interface (CNI) and service mesh.

### Why?
- **eBPF-based:** High performance, kernel-level networking
- **Network Policies:** Advanced L3-L7 security policies
- **Gateway API:** Native ingress via Cilium Gateway API
- **Observability:** Hubble for network visibility

### Alternatives
- ❌ **Calico** — No Gateway API support, less modern
- ❌ **Flannel** — Too basic, no advanced features
- ❌ **Weave** — Project maintenance concerns

### Trade-offs
- ✅ Best-in-class networking
- ✅ Replaces need for separate ingress controller
- ❌ Complex debugging
- ❌ Requires kernel 4.9+

---

## ADR-003: ArgoCD for GitOps

**Status:** Accepted
**Date:** 2025-12-22

### Decision
**ArgoCD** for declarative, GitOps continuous delivery.

### Why?
- **Git as Source of Truth:** All config in Git
- **Automatic Sync:** Self-healing deployments
- **Rollback:** Easy revert via Git history
- **Multi-cluster:** Ready for future expansion

### Alternatives
- ❌ **Flux CD** — Less mature UI, more complex setup
- ❌ **Manual kubectl** — No automation, error-prone
- ❌ **Helm only** — No drift detection

### Trade-offs
- ✅ Declarative infrastructure
- ✅ Audit trail via Git
- ❌ Extra complexity layer
- ❌ Learning curve

---

## ADR-004: External Secrets with 1Password

**Status:** Accepted
**Date:** 2025-12-23

### Decision
**External Secrets Operator** with **1Password** as secrets backend.

### Why?
- **Security:** Secrets not in Git
- **Central Management:** Single source for secrets
- **1Password:** Already used, family shared vaults
- **Kubernetes-native:** Automatic sync to Secrets

### Alternatives
- ❌ **Sealed Secrets** — Secrets encrypted in Git (not ideal)
- ❌ **HashiCorp Vault** — Overkill for homelab
- ❌ **Manual Secrets** — No version control, manual work

### Trade-offs
- ✅ Centralized secret management
- ✅ No secrets in Git
- ❌ Dependency on 1Password Connect
- ❌ Extra infrastructure component

---

## ADR-005: Longhorn for Persistent Storage

**Status:** Accepted
**Date:** 2025-12-24

### Decision
**Longhorn** as distributed block storage for Kubernetes.

### Why?
- **Cloud-native:** Kubernetes-native storage
- **Replication:** Data redundancy across nodes
- **Snapshots:** Built-in backup/restore
- **Simple:** Easy setup and management UI

### Alternatives
- ❌ **Rook/Ceph** — Complex, overkill for 3-node cluster
- ❌ **OpenEBS** — Less mature
- ❌ **NFS** — Single point of failure, no replication

### Trade-offs
- ✅ Data redundancy
- ✅ Easy backups
- ❌ Network overhead for replication
- ❌ Performance tradeoff vs local storage

---

## ADR-006: Cert-Manager with Let's Encrypt

**Status:** Accepted
**Date:** 2025-12-25

### Decision
**Cert-Manager** with **Let's Encrypt** for automatic TLS certificates.

### Why?
- **Automation:** Automatic cert provisioning and renewal
- **Free:** Let's Encrypt wildcard certificates
- **Kubernetes-native:** CRDs for certificate management
- **DNS Challenge:** Wildcard certs via Cloudflare DNS

### Alternatives
- ❌ **Manual certs** — Renewal overhead, error-prone
- ❌ **Traefik ACME** — Less flexible, ingress-specific
- ❌ **Self-signed** — Browser warnings, no trust

### Trade-offs
- ✅ Zero-touch certificate management
- ✅ Valid browser trust
- ❌ Rate limits (50 certs/week)
- ❌ Dependency on Let's Encrypt uptime

---

## ADR-007: Prometheus Stack for Monitoring

**Status:** Accepted
**Date:** 2025-12-26

### Decision
**Prometheus Stack** (Prometheus + Grafana + AlertManager) for observability.

### Why?
- **Industry Standard:** De facto monitoring for Kubernetes
- **Pull-based:** Metrics via ServiceMonitor CRDs
- **Grafana:** Rich dashboards and visualization
- **Alerting:** AlertManager for notifications

### Alternatives
- ❌ **Datadog/New Relic** — Expensive for homelab
- ❌ **InfluxDB** — Less Kubernetes-native
- ❌ **ELK Stack** — Overkill, resource-heavy

### Trade-offs
- ✅ Complete observability stack
- ✅ Rich ecosystem
- ❌ Resource intensive
- ❌ Complex alert configuration

---

## ADR-008: Authentik as SSO Provider

**Status:** Accepted
**Date:** 2025-12-27

### Decision
**Authentik** as centralized SSO/authentication provider.

### Why?
- **Open Source:** Self-hosted, no vendor lock-in
- **Protocols:** OIDC, OAuth2, SAML, LDAP support
- **User Management:** Groups, policies, enrollment flows
- **Modern UI:** Better UX than Keycloak

### Alternatives
- ❌ **Keycloak** — More complex, Java-based, heavyweight
- ❌ **Authelia** — Less feature-rich
- ❌ **OAuth2 Proxy** — No user management

### Trade-offs
- ✅ Single sign-on for all services
- ✅ Centralized user management
- ❌ Extra infrastructure dependency
- ❌ Not all apps support OIDC natively

---

## ADR-009: Cilium Gateway API for Ingress

**Status:** Accepted
**Date:** 2025-12-28

### Decision
**Cilium Gateway API** for ingress traffic management.

### Why?
- **Standard:** Kubernetes Gateway API (successor to Ingress)
- **Integrated:** Native Cilium feature, no extra controller
- **Flexible:** HTTPRoute, TLSRoute support
- **Performance:** eBPF-based, kernel-level routing

### Alternatives
- ❌ **Nginx Ingress** — Extra component, legacy Ingress API
- ❌ **Traefik** — More resource overhead
- ❌ **Istio Gateway** — Overkill, service mesh not needed

### Trade-offs
- ✅ Modern Gateway API
- ✅ No extra ingress controller
- ❌ Newer API, fewer examples
- ❌ Limited middleware options vs Traefik

---

## ADR-010: CloudNative-PG for PostgreSQL

**Status:** Accepted
**Date:** 2026-01-05

### Decision
**CloudNative-PG** as PostgreSQL operator.

### Why?
- **Kubernetes-native:** CRDs for database clusters
- **HA:** Automatic failover, streaming replication
- **Backups:** S3-compatible backup/restore (Barman)
- **Simple:** Easier than Patroni/Zalando operator

### Alternatives
- ❌ **Zalando Postgres Operator** — More complex
- ❌ **Crunchy Data** — Overkill for homelab
- ❌ **External Postgres** — No HA, manual management

### Trade-offs
- ✅ HA database clusters
- ✅ Automatic backups
- ❌ Storage overhead for replicas
- ❌ More complex than single instance

---

## ADR-011: Home Assistant on Kubernetes

**Status:** Accepted
**Date:** 2026-01-15

### Decision
**Home Assistant** migration to Kubernetes.

### Why?
- **Unified Platform:** All apps on Kubernetes
- **GitOps:** HA config as code
- **Backups:** Longhorn snapshots
- **Scaling:** Better resource management

### Challenges
- **hostNetwork:** Required for mDNS/discovery
- **USB Devices:** Zigbee coordinator via node affinity
- **PostgreSQL:** Migrated recorder database to CNPG

### Trade-offs
- ✅ Declarative configuration
- ✅ Integrated monitoring
- ❌ More complex than HA OS
- ❌ hostNetwork required

---

## ADR-012: Zigbee2MQTT + EMQX for IoT

**Status:** Accepted
**Date:** 2026-01-16

### Decision
**EMQX** as centralized MQTT broker, **Zigbee2MQTT** for Zigbee devices.

### Why?
- **Centralized:** Single MQTT broker for all IoT
- **Scalable:** EMQX clustering support
- **Reliable:** Better than Mosquitto for production
- **Dashboard:** Built-in management UI

### Architecture
```
Zigbee Devices → Zigbee2MQTT → EMQX → Home Assistant
                                  ↓
                            Other MQTT clients
```

### Trade-offs
- ✅ Centralized MQTT infrastructure
- ✅ Better than embedded HA MQTT
- ❌ Extra component to manage
- ❌ More complex than Mosquitto

---

## ADR-013: Firefly III - Personal Finance Manager

**Status:** Accepted
**Date:** 2026-02-08

### Decision
**Firefly III** for personal finance management (chosen over Actual Budget).

### Why?
- **Self-hosted:** Privacy, no cloud dependency
- **Feature-rich:** Budgets, reports, rules, recurring transactions
- **PostgreSQL:** Uses CNPG shared cluster
- **Active Development:** Regular updates

### Trade-offs
- ✅ Complete finance management
- ✅ Self-hosted privacy
- ❌ No native OIDC/SSO (yet)
- ❌ Relies on manual transaction imports

---

## ADR-014: Database Initialization via GitOps Jobs

**Status:** Accepted
**Date:** 2026-01-28

### Decision
**ArgoCD PostSync Jobs** for idempotent database initialization.

### Why?
- **GitOps:** Database provisioning in Git
- **Idempotent:** Safe to rerun, uses DO blocks
- **Peer Auth:** kubectl exec avoids password auth
- **Automatic:** Runs after cluster deployment

### What Doesn't Work
- ❌ **postInitSQL** — Only runs at bootstrap, not for existing clusters
- ❌ **TCP connections** — Password auth fails with CNPG
- ❌ **Heredocs with kubectl exec** — Silent failures

### Implementation
```yaml
# ArgoCD PostSync hook
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    argocd.argoproj.io/hook: PostSync
spec:
  template:
    spec:
      containers:
        - name: init-db
          image: bitnami/kubectl:latest
          # Find primary pod + kubectl exec with inline SQL
```

### Trade-offs
- ✅ Fully GitOps database provisioning
- ✅ Idempotent, safe to rerun
- ❌ Jobs remain in cluster (HookSucceeded policy)
- ❌ Requires RBAC for pod/exec

---

## ADR-015: NetBox - IPAM/DCIM Platform

**Status:** Accepted
**Date:** 2026-02-09

### Decision
**NetBox** for IP Address Management (IPAM) and Data Center Infrastructure Management (DCIM).

### Why?
- **Network Documentation:** Central platform for VLANs, IP ranges, devices
- **Industry Standard:** De facto tool for network infrastructure docs
- **API-first:** REST API for automation (Terraform, Ansible)
- **OIDC Support:** Native SSO integration via python-social-auth
- **PostgreSQL:** Uses CNPG shared cluster

### Alternatives
- ❌ **Spreadsheets** — No API, error-prone, no audit trail
- ❌ **phpIPAM** — Less feature-rich, no DCIM
- ❌ **Netdisco** — Device discovery only, no full IPAM

### Trade-offs
- ✅ Complete network documentation platform
- ✅ SSO via Authentik (OIDC)
- ✅ API automation ready
- ❌ Requires custom OIDC pipeline for user field mapping
- ❌ Heavy application (2Gi memory limit needed)

---

## ADR-016: Homarr - Homelab Dashboard

**Status:** Accepted
**Date:** 2026-02-09

### Decision
**Homarr** as centralized homelab dashboard.

### Why?
- **Modern UI:** React/Next.js, beautiful dashboard
- **Service Integrations:** Native support for Proxmox, Sonarr, Radarr, etc.
- **OIDC Support:** SSO via Authentik
- **Customizable:** Widgets, layouts, per-user boards
- **PostgreSQL:** Uses CNPG shared cluster

### Why Not Homer/Heimdall?
- ❌ **Homer** — Static YAML, no SSO, no integrations
- ❌ **Heimdall** — PHP-based, outdated, limited SSO
- ❌ **Dashy** — No native OIDC, less polished

### Trade-offs
- ✅ Best-in-class homelab dashboard
- ✅ SSO via Authentik (OIDC)
- ✅ Service integrations out-of-the-box
- ❌ Memory hungry (1Gi limit required)
- ❌ OIDC issuer URL must have trailing slash (quirk)

---

## Implementation Roadmap

### Planned

| Component | Priority | Status | Notes |
|-----------|----------|--------|-------|
| **Cloudflare Tunnel** | Medium | Planned | Secure external access without port forwarding |
| **Firefly III SSO** | Medium | Deferred | Waiting on native OIDC support (#10662) |
| **Immich Photo Management** | Low | Planned | ML-powered photos, requires 100-500Gi storage |
| **Talos SecureBoot** | Low | Planned | Requires full node reinstallation |
| **Per-hostname SSL Certs** | Low | Planned | Migrate from wildcard to per-hostname |
| **Tailscale** | Low | On Hold | WireGuard already provides sufficient remote access |

### Recently Completed
- ✅ **CNPG Backup Validation** — Weekly automated restore testing from S3 (2026-02-09)
- ✅ **NetBox** — IPAM/DCIM platform (2026-02-09)
- ✅ **Homarr** — Homelab dashboard (2026-02-09)
- ✅ **Firefly III** — Personal finance management (2026-02-08)
- ✅ **Database GitOps Jobs** — Automatic database initialization (2026-01-28)
- ✅ **Home Assistant Migration** — Moved to Kubernetes (2026-01-15)
- ✅ **EMQX MQTT Broker** — Centralized IoT messaging (2026-01-16)

---

## ADR Principles

### Keep It Short
- ADR = Decision + Rationale + Trade-offs
- Technical details → configuration docs
- Focus on **WHY**, not **HOW**

### Update When Needed
- Status: Accepted → Superseded → Deprecated
- Add superseded-by link when decision changes
- Don't delete old ADRs, mark as superseded
