# AOD simulator

Self-hosted [Area Occupancy Detection simulator](https://github.com/Hankanman/Area-Occupancy-Detection), so
`run_analysis` calls from Home Assistant stay on the LAN instead of going to the hosted upstream instance.

- URL: `https://aod.svc.damman.tech/simulator/` (svc-gateway, LAN only). The API is on the same origin under `/api/`
  (`/api/analyze`, `/api/load`, `/api/get-purposes`).
- Chart: `resources/gitops-config/applications/aod-simulator/`, Argo app `sync-app/templates/aod-simulator.yaml` (wave 5, tier-3).
- Images: built in the private repo `wouterdamman/aod-simulator-image` and pushed to the private
  `ghcr.io/wouterdamman/aod-simulator-{api,web}`, tagged `<upstream tag>-<revision>`. `image.tag` in `values.yaml`
  must match `VERSION` in that repo; there is no Renovate tracking for these images.

## Pod

One pod, two containers: `api` (gunicorn, 2 workers, port 10000) and `web` (nginx, port 8080, proxies `/api/` to
`127.0.0.1:10000`, `/healthz` liveness, `/readyz` readiness that also checks the api). Namespace PSA `restricted`,
read-only root filesystem, all capabilities dropped, seccomp RuntimeDefault, no service account token, `/tmp` emptyDir.
1 replica, no scale-to-zero (nothing in the cluster provides it).

## Security

- The API has no authentication. Access control is the LAN-only svc-gateway; there is no Authentik layer.
- CiliumNetworkPolicy: ingress only on 8080, `egressDeny` to everything (no DNS, no internet). The UI assets that
  upstream loads from CDNs (Shoelace, Chart.js, MathJax, fonts) are vendored into the web image at build time.
- Pulling the private images uses the `aod-simulator-ghcr` pull secret, created by an ExternalSecret from the
  1Password item `aod-simulator-ghcr` (field `token`, a GitHub PAT with `read:packages`) in vault `KubernetesSecrets`.

## Home Assistant

Point the integration's simulator/API base URL at `https://aod.svc.damman.tech` (configured in the HA repo, not here).
