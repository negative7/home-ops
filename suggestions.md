# Cluster app comparison vs. reference repos

Comparison of apps deployed in this cluster against [`onedr0p/home-ops`](https://github.com/onedr0p/home-ops) and
[`bjw-s-labs/home-ops`](https://github.com/bjw-s-labs/home-ops), the two reference repos this repo's `AGENTS.md`
already treats as its source of truth for conventions. Generated 2026-07-31.

Not included as "gaps" since they're already deliberate, tracked decisions: the Rook-Ceph/OpenEBS → Miroir storage
migration (see `AGENTS.md` TODO), Flux CD, 1Password External Secrets, Envoy Gateway/Gateway API, and Kopiur.

## Apps to consider adopting

**Downloads** (this repo has bazarr/prowlarr/radarr/recyclarr/sonarr only)

| App | Purpose | In |
| --- | --- | --- |
| autobrr | IRC/announce-based torrent automation | both |
| qbittorrent + qui | torrent client + modern WebUI manager | both |
| sabnzbd | usenet downloader | both |
| slskd | Soulseek daemon | onedr0p |
| shelfmark | ebook downloader/library tool | bjw-s-labs |
| agregarr / brrpolice / deduparr | *arr indexer-aggregation, release QC, library dedup | onedr0p (niche, low priority) |

Note: `autobrr`, `sabnzbd`, and a gluetun+qbittorrent+qui stack already run on the `lviv` NAS via Docker Compose
(`docker/lviv/downloads/`) — so this "gap" is largely already covered outside Kubernetes. Worth a conscious
decision either way, not a blind port.

**Media**

| App | Purpose | In |
| --- | --- | --- |
| audiobookshelf | audiobook/podcast server | bjw-s-labs |
| go2rtc | WebRTC/RTSP camera restreamer (pairs with scrypted) | onedr0p |
| tautulli | Plex stats/monitoring | onedr0p |
| dispatcharr | IPTV/EPG channel manager | bjw-s-labs |

**Home automation** (new category — this repo only has `home/scrypted`)

| App | Purpose | In |
| --- | --- | --- |
| home-assistant | home automation hub | both |
| frigate | NVR/camera AI detection | bjw-s-labs |
| mosquitto, zigbee2mqtt, zwave-js | MQTT/Zigbee/Z-Wave stack | onedr0p |

Only relevant if there's an actual home-automation hardware setup to back it — not a generic recommendation.

**AI** (new category, bjw-s-labs only: litellm/litellm-operator, open-webui, plus smaller pieces like llmkube,
memini, context7-mcp, ha-mcp) — only worth it if there's demand for self-hosted LLM serving.

**Selfhosted**

| App | Purpose | In |
| --- | --- | --- |
| freshrss | RSS reader | bjw-s-labs |
| searxng | private search | bjw-s-labs |
| paperless | document management | bjw-s-labs |
| nextcloud | file sync | bjw-s-labs |
| manyfold | 3D model library | bjw-s-labs |
| webhook | generic webhook receiver | bjw-s-labs |
| kanidm | self-hosted IdP/SSO | bjw-s-labs |
| forgejo | self-hosted git+CI | bjw-s-labs |

**Network / kube-system**

| App | Purpose | In |
| --- | --- | --- |
| multus | secondary CNI interfaces | both |
| drm-exporter, generic-device-plugin | GPU/USB device metrics & plugin | onedr0p |
| snmp-exporter | SNMP device metrics | onedr0p |
| konflate | evidence-based Flux auto-merge/promotion tool | both — see below |

## Apps unique to this repo

`home/scrypted`, `media/jellyplex-watched`, `observability/headlamp`, `openebs/openebs` (being retired, tracked),
`selfhosted/spoolman`, `network/external-services`.

## Version/config gaps on shared apps

Sampled ~15 shared infra apps (cert-manager, envoy-gateway, kube-prometheus-stack, external-dns, cloudflared,
reloader, silence-operator, dragonfly-operator, spegel, atuin, actual, karakeep, jellyfin, plex). Renovate is
clearly keeping this repo current: cert-manager (v1.21.1), envoy-gateway (1.8.3), reloader (2.2.14),
silence-operator (0.20.1), dragonfly-operator (v1.6.1), external-dns (1.21.1), and app-template 5.0.1 for
atuin/karakeep/jellyfin/plex/actual/cloudflared all match one or both reference repos exactly.
kube-prometheus-stack (87.21.0) sits between bjw-s-labs (87.19.2, this repo ahead) and onedr0p (88.0.0, onedr0p
ahead) — not worth chasing. The envoy-gateway and kube-prometheus-stack HelmReleases are byte-for-byte identical
to bjw-s-labs's, confirming that repo as the direct structural template.

### Recommended: modernize `system/descheduler`

This is the one real, actionable gap found.

- **Chart delivery**: this repo still uses the legacy `HelmRepository` + `chart.spec` pattern at chart `0.32.2`.
  Every other app here — and both reference repos — use `OCIRepository` + `chartRef`, at chart `0.36.0`.
- **Policy schema**: this repo's `DefaultEvictor` uses the old `evictFailedBarePods`/`evictLocalStoragePods`/
  `evictSystemCriticalPods`/`nodeFit` args. bjw-s-labs's newer schema uses `podProtections.defaultDisabled` plus
  an explicit `metricsProviders: KubernetesMetrics`.
- **Missing plugins**: bjw-s-labs enables `LowNodeUtilization` and `RemoveFailedPods`, which this repo's profile
  omits entirely — meaning descheduler here currently only handles anti-affinity/taint/topology-spread
  violations and does no utilization-based rebalancing or failed-pod cleanup.

**Suggested action**: convert to `OCIRepository`/`chartRef`, bump to `0.36.0`, and adopt the fuller policy
(`podProtections.defaultDisabled`, `metricsProviders`, `LowNodeUtilization`, `RemoveFailedPods`).

### Minor/cosmetic, not worth separate action

- `selfhosted/actual` uses the `actual-server` image vs. bjw-s-labs's `actual` (same project, likely a rename in
  flight upstream), with a 256M vs 512M memory limit here.
- `system/spegel` correctly sets `appendMirrors`/`containerdRegistryConfigPath` for Talos's `/etc/cri/conf.d/hosts`
  (onedr0p does the same), but has no `GrafanaDashboard` CR wired up like onedr0p's does — low-value addition
  given `observability/grafana` already exists here.

## Repo-level pattern differences

- Both reference repos pull some charts/images through `oci://mirror.gcr.io/...` (e.g. the envoy-gateway chart,
  cloudflared image) to dodge Docker Hub rate limits; this repo pulls those two directly from `docker.io`. Low
  risk, easy swap if Docker Hub throttling ever becomes a problem.
- onedr0p and bjw-s-labs both pin CLI tool versions via `mise` (`.mise.toml`); this repo has no pinned-toolchain
  mechanism and relies on whatever `just`/`flux`/`talosctl`/`helm` happen to be installed locally. Worth adopting
  for reproducibility across machines.
- onedr0p uses `lefthook` for git pre-commit hooks (YAML lint/fmt before a commit is even made); this repo only
  lints in CI (`.github/workflows/lint.yaml`), so malformed YAML can be committed locally before being caught.
  Worth adopting to shorten the feedback loop.
- bjw-s-labs has moved CI/PR automation off GitHub Actions onto self-hosted Forgejo Actions
  (`.forgejo/workflows`), including a custom AI PR-reviewer and the `konflate` evidence-based auto-merge tool.
  The Forgejo migration itself is a much bigger structural bet, probably not worth mirroring here — but
  `konflate` alone (also present in onedr0p, works as a standalone Flux app) is worth evaluating independent of
  that move, since Renovate PR review/merge toil is a recurring cost in this repo too.
- bjw-s-labs's namespace taxonomy (`downloads`, `media`, `observability`, `selfhosted`, `system`) is a near-exact
  match for this repo's — confirming it as the primary structural template. onedr0p instead lumps most apps into
  a flat `default` namespace and uses `o11y` instead of `observability`.
- Both reference repos have an `ai` namespace for self-hosted LLM tooling; this repo has none. Only worth adding
  if there's real demand for local LLM hosting.
- Aside from descheduler, this repo's Renovate setup (`.renovate/*.json5` split by concern) is at least as
  granular as both references' — no gap there.

## Suggested next steps, roughly in priority order

1. Modernize `descheduler` (`OCIRepository`/`chartRef`, chart `0.36.0`, fuller policy) — concrete, low-risk,
   closes a real functionality gap (no utilization-based rebalancing or failed-pod cleanup today).
2. Evaluate `konflate` for Renovate PR auto-merge — both reference repos run it; could reduce manual PR toil.
3. Adopt `mise` for pinned CLI tool versions and `lefthook` for local pre-commit YAML lint — both are cheap,
   repo-hygiene wins with no architectural risk.
4. Everything else above (new apps/namespaces like `ai`, `home-automation`, additional `downloads`/`media`/
   `selfhosted` apps) is a "do you actually want this service" question, not a "you're behind" gap — evaluate
   per-app against actual need rather than adopting wholesale.
