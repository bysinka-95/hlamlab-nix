# Grafana dashboards

Every `*.json` in this directory is provisioned into Grafana (see `grafana.nix`).

## Datasource UIDs are pinned

The two datasources have fixed UIDs so dashboards can reference them deterministically:

| Datasource | UID          |
|------------|--------------|
| Prometheus | `prometheus` |
| Loki       | `loki`       |

## Adding a dashboard from grafana.com

Dashboards exported from grafana.com contain an `__inputs` block with a
`${DS_PROMETHEUS}` / `${DS_LOKI}` placeholder. The Grafana **UI import wizard**
substitutes those, but **file provisioning does not** — which is why an
un-processed dashboard renders `datasource ${DS_PROMETHEUS} not found`.

`grafana.nix` fixes this automatically: at build time every JSON here is passed
through `sed`, rewriting `${DS_PROMETHEUS}` → `prometheus` and `${DS_LOKI}` →
`loki`. So you can drop a raw grafana.com export straight in:

1. Download the dashboard JSON (e.g. node-exporter-full = grafana.com ID 1860).
2. Save it here as `<name>.json`.
3. `git add` it (untracked files are invisible to Nix flakes).
4. Rebuild — the placeholder is rewritten, the dashboard just works.

If a dashboard uses a differently-named datasource input (not `DS_PROMETHEUS`
/ `DS_LOKI`), add a matching `sed` line to the `dashboards` derivation in
`grafana.nix`.

## Custom dashboards (this repo)

- **homelab-overview** — the entry point. Host/fleet header → per-container
  CPU/mem/net/disk (+ % of MemoryMax / CPU quota) → per-service drill-down → logs.
  Variables `$container`, `$service`, `$search` filter the whole board top to bottom.
- **cadvisor-containers** — container internals: per-service memory/CPU (stacked),
  memory composition (rss/cache/swap), CPU throttling, processes/threads, OOM events.

### cAdvisor label convention (how the filtering works)

cAdvisor labels every cgroup with a single `id` = its full path. There is **no**
`name` label for nspawn cgroups, so all queries key on `id`:

| Scope | `id` shape |
|-------|-----------|
| host root | `/` |
| container root (whole container) | `/machine.slice/container@<name>.service` |
| a service inside a container | `/machine.slice/container@<name>.service/payload/**/<svc>.service` |

- Container name is pulled into a clean legend with
  `label_replace(<expr>, "container", "$1", "id", "^.*container@([^/]+)\.service.*$")`.
- Service name: `label_replace(..., "svc", "$1", "id", "^.*/([^/]+)\.service$")`.
- The `$container` variable is `label_values(container_last_seen, id)` filtered by the
  extraction regex `/container@(?<value>[^/]+?)\.service$/` — the trailing `$` makes it
  match container **roots** only (service ids have more path after `.service`).

`machine_cpu_cores` / `machine_memory_bytes` give host totals for the % gauges.

**Two cAdvisor gotchas** (why some metrics don't sit on the container-root `id`):

- **Network** is reported on the host root `id="/"` with `interface="ve-<name>"` (the
  container's veth), *not* on `container@<name>.service`. Query it as
  `container_network_receive_bytes_total{id="/",interface=~"ve-($container)"}` and pull the
  name from the `interface` label.
- **Disk**: `container_fs_*` is a *device total* duplicated identically across every cgroup —
  useless per-container. Real per-container disk is `container_blkio_device_usage_total`
  (per-cgroup, with `operation="Read"/"Write"`).
- **CPU**: `container_cpu_usage_seconds_total` carries a `cpu="total"` label; `sum by(id)` it
  before dividing by `container_spec_cpu_quota/period` (which have only `id`), else vector
  matching drops everything.

## Recommended starters (grafana.com)

- **1860** node-exporter-full — host metrics (job `node`). Containers share the host kernel, so
  their own exporters (job `node-container`) carry only systemd unit state, filesystem and netdev;
  use the cAdvisor dashboards for real per-container CPU/memory usage.
- **13639** Loki logs / quick search.
- **17346** Traefik official.
