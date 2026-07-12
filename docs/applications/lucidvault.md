# LucidVault

LucidVault is an AI-powered knowledge vault that fetches bookmarks and videos from Raindrop and YouTube, enriches them with Ollama (LLM), and stores structured notes in an Obsidian vault synced via CouchDB.

## Overview

**Purpose**: Automated knowledge management pipeline:
- Fetches bookmarks from Raindrop (articles, YouTube videos)
- Extracts YouTube transcripts via Supadata API
- Summarises and structures content using Ollama LLM
- Stores output as Markdown notes in an Obsidian vault (PVC)
- Exposes vault via MCP HTTP server for Claude Code integration
- Syncs vault to Obsidian desktop via CouchDB + Self-hosted LiveSync

**Status**: ✅ Deployed (2026-07-12) — MCP at https://lucidvault.svc.damman.tech, CouchDB at https://couchdb.svc.damman.tech

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    External Sources                             │
│   Raindrop (bookmarks)   YouTube (transcripts via Supadata)    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                  lucidvault-pipeline (Deployment)               │
│  - Polls Raindrop every 5 minutes                               │
│  - Fetches transcripts via Supadata                             │
│  - Enriches with Ollama (gemma3:12b)                            │
│  - Writes Markdown to vault PVC (/vault)                        │
└──────────────────────────┬──────────────────────────────────────┘
                           │ RWO PVC (lucidvault-vault, 20Gi)
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐
│ lucidvault   │  │  livesync-   │  │   lucidvault-mcp       │
│    -mcp      │  │    bridge    │  │   (MCP HTTP server)    │
│ (port 8080)  │  │ (Deployment) │  │   Claude Code tool     │
└──────┬───────┘  └──────┬───────┘  └────────────────────────┘
       │                 │
       │          ┌──────▼──────────────────┐
       │          │   lucidvault-couchdb    │
       │          │   (StatefulSet, :5984)  │
       │          │   CouchDB 3 single-node │
       │          └──────┬──────────────────┘
       │                 │
       ▼                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                    svc-gateway (10.0.10.240)                    │
│   lucidvault.svc.damman.tech   couchdb.svc.damman.tech         │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                     ┌────────────────────────┐
                     │  Obsidian (macOS)      │
                     │  Self-hosted LiveSync  │
                     │  E2EE enabled          │
                     └────────────────────────┘
```

### Component Roles

| Component | Role |
|-----------|------|
| `lucidvault-pipeline` | Fetch → enrich → write notes to PVC |
| `lucidvault-mcp` | MCP HTTP server exposing vault to Claude Code |
| `lucidvault-livesync-bridge` | Sync vault PVC ↔ CouchDB (pitazzo/livesync-bridge) |
| `lucidvault-couchdb` | CouchDB instance for Obsidian LiveSync replication |
| `lucidvault-raindrop-cleanup` | Daily CronJob deleting Raindrop bookmarks > 3 days |

## Technical Specifications

| Component | Image |
|-----------|-------|
| Pipeline + MCP | ghcr.io/bamaas/lucidvault:latest |
| LiveSync Bridge | pitazzo/livesync-bridge:latest |
| CouchDB | couchdb:3 |
| Raindrop Cleanup | python:3.12-slim |

### Resource Requirements

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| pipeline | 50m | 500m | 64Mi | 256Mi |
| mcp | 50m | 200m | 64Mi | 128Mi |
| livesync-bridge | 50m | 200m | 64Mi | 128Mi |
| couchdb | 50m | 500m | 128Mi | 512Mi |
| raindrop-cleanup | 10m | 100m | 32Mi | 64Mi |

### Storage

| Purpose | Size | Storage Class | Mount Path |
|---------|------|---------------|-----------|
| Obsidian vault | 20Gi | longhorn-standard | /vault (pipeline, mcp, livesync-bridge) |
| CouchDB data | 5Gi | longhorn-standard | /opt/couchdb/data (StatefulSet volumeClaimTemplate) |

Both pipeline and MCP use `Recreate` strategy — vault PVC is RWO. All pods sharing the PVC are pinned to the same node via `podAffinity` on `component: pipeline`.

## Secrets Management

| Secret | 1Password Item | Field | Purpose |
|--------|---------------|-------|---------|
| OLLAMA_API_KEY | lucidvault-ollama | api_key | Ollama Cloud API access |
| RAINDROP_ACCESS_TOKEN | lucidvault-raindrop | access_token | Raindrop API |
| SUPADATA_API_KEY | lucidvault-supadata | api_key | YouTube transcript API |
| COUCHDB_USER | lucidvault-couchdb | username | CouchDB admin user |
| COUCHDB_PASSWORD | lucidvault-couchdb | password | CouchDB admin password |
| COUCHDB_SECRET | lucidvault-couchdb | secret | CouchDB Erlang cookie |
| LIVESYNC_PASSPHRASE | lucidvault-livesync-passphrase | password | Obsidian E2EE passphrase |

Two `ExternalSecret` CRs: `lucidvault-secrets` and `lucidvault-couchdb-secrets`.

## Network Configuration

| Route | Gateway | Hostname | Backend | Port |
|-------|---------|----------|---------|------|
| MCP HTTP | svc-gateway | lucidvault.svc.damman.tech | lucidvault-mcp | 8080 |
| CouchDB | svc-gateway | couchdb.svc.damman.tech | lucidvault-couchdb | 5984 |

DNS managed automatically by external-dns.

## CouchDB Configuration

Single-node setup with CORS enabled for Obsidian LiveSync.

```ini
[couchdb]
single_node = true

[chttpd]
require_valid_user = true
enable_cors = true

[cors]
origins = app://obsidian.md,capacitor://localhost,http://localhost
credentials = true
methods = GET, PUT, POST, HEAD, DELETE
headers = accept, authorization, content-type, origin, referer
```

Initialised via ArgoCD PostSync Job (`lucidvault-couchdb-init`) that calls `/_cluster_setup` and creates the `lucidvault` database. Job auto-deletes on success (`HookSucceeded`).

## Obsidian LiveSync

LiveSync Bridge configuration (peers):

```json
{
  "peers": [
    {
      "type": "couchdb",
      "name": "lucidvault-remote",
      "url": "http://lucidvault-couchdb:5984",
      "database": "lucidvault",
      "passphrase": "<from secret>",
      "useRemoteTweaks": true
    },
    {
      "type": "storage",
      "name": "lucidvault-storage",
      "baseDir": "./data/",
      "scanOfflineChanges": true
    }
  ]
}
```

Bridge mounts vault PVC at `/app/data`. Config rendered at startup by `busybox` initContainer via `sed` from ConfigMap template. Credentials injected from `lucidvault-couchdb-secrets`.

**E2EE passphrase** stored in 1Password as `lucidvault-livesync-passphrase`. Same passphrase must be configured in the Obsidian Self-hosted LiveSync plugin.

## Raindrop Cleanup CronJob

Runs daily at 02:00 UTC. Fetches all bookmarks from Raindrop inbox (collection 0), deletes those older than 3 days.

```
Schedule: 0 2 * * *
backoffLimit: 2
restartPolicy: OnFailure
```

Manual trigger:
```bash
kubectl create job --from=cronjob/lucidvault-raindrop-cleanup raindrop-cleanup-test -n lucidvault
kubectl logs -n lucidvault -l job-name=raindrop-cleanup-test -f
```

## Claude Code Integration

MCP server exposed at `lucidvault.svc.damman.tech`. Available tools:
- `related_notes` — bidirectional graph traversal for a wiki page
- `expand_graph` — explore connected concepts
- `add_bookmark`, `add_note`, `edit_page`, `delete_page`, `update_wiki`

Global `~/.claude/CLAUDE.md` instructs Claude to check vault before answering technical questions about infra, Kubernetes, GitOps, and tooling.

## Troubleshooting

### LiveSync Bridge: PermissionDenied on localStorage

Deno's localStorage fails when `HOME` is unwritable (`/nonexistent` for UID 65534).

**Fix**: Set `HOME=/tmp` and `DENO_DIR=/tmp/deno` env vars on the container.

### LiveSync Bridge: "database is closed" on first start

Race condition: storage peer dispatches offline changes before CouchDB peer's local PouchDB has finished initialising. Happens once when CouchDB database is detected as rebuilt.

**Fix**: Kubernetes restarts the container automatically. Second run succeeds because the CouchDB database is no longer in a "rebuilt" state.

### LiveSync Bridge: modules re-downloaded on every restart

`DENO_DIR=/tmp/deno` is ephemeral (container restart clears `/tmp`). Expected behaviour — Deno re-downloads and re-caches on each start. Not a functional issue, adds ~30s to startup.

### soul.md empty in Obsidian

`soul.md` is mounted via ConfigMap subPath in the pipeline pod — overlays the PVC file in-process but does not write to the PVC. The livesync-bridge reads the PVC directly.

**Fix**: `seed-soul` initContainer in the pipeline deployment copies ConfigMap `soul.md` to the vault PVC on every pod start.

### Obsidian frontmatter shows as raw red text

YAML values containing `:` must be quoted. Pipeline bug: titles like `Advanced Deployment Strategies with ArgoCD: ApplicationSets & ...` break frontmatter parsing.

**Workaround**: Quote the title manually in Obsidian. Bug reported to `bamaas/lucidvault`.

## Changelog

### 2026-07-12
- ✅ Initial deployment: pipeline, MCP, CouchDB, LiveSync Bridge
- Obsidian Self-hosted LiveSync configured with E2EE
- Fixed LiveSync Bridge: HOME/DENO_DIR, correct peers config format, scanOfflineChanges
- Fixed soul.md: seed-soul initContainer writes ConfigMap content to PVC
- Added `runAsNonRoot: true` to livesync-bridge securityContext
- Added daily Raindrop cleanup CronJob (bookmarks > 3 days)
- Global Claude Code instruction to check vault before answering technical questions
