# Grafana dashboards

Grafana loads each `*.json` file in this directory (see `grafana.nix`).

## Dashboards in this directory

| File                       | Source                                   | Contents                                                                                       |
|----------------------------|------------------------------------------|------------------------------------------------------------------------------------------------|
| `homelab-overview.json`    | this repo                                | Start here. Host header, CPU/RAM/network/disk per container, drill-down per service, logs      |
| `cadvisor-containers.json` | this repo                                | Container internals: memory and CPU per service, memory parts, CPU throttling, OOM events      |
| `node-exporter-full.json`  | grafana.com 1860                         | Host metrics (job `node`)                                                                      |
| `logs-app.json`            | grafana.com 13639                        | Loki log viewer                                                                                |
| `traefik-dashboard.json`   | grafana.com 17346                        | Traefik                                                                                        |
| `cloudflare-tunnel.json`   | grafana.com 17457                        | cloudflared tunnel                                                                             |
| `crowdsec-overview.json`   | CrowdSec v5 Overview, changed for 1.8    | CrowdSec: decisions, alerts, parsers, buckets, AppSec (job `crowdsec`)                         |

In `homelab-overview`, the variables `$container`, `$service` and `$search` filter the whole board.

The per-container exporters (job `node-container`) give only systemd unit state, file system and
network data, because the containers share the host kernel. For real CPU and memory use per
container, use the cAdvisor dashboards.

`crowdsec-overview` comes from
[crowdsecurity/grafana-dashboards](https://github.com/crowdsecurity/grafana-dashboards). The
upstream file is for CrowdSec 1.5. This copy uses the bucket counter name of 1.8, shows 0 instead
of an old value when there are no decisions, and has an extra AppSec panel.

## Datasource UIDs are fixed

The two datasources have fixed UIDs, so dashboards can refer to them:

| Datasource | UID          |
|------------|--------------|
| Prometheus | `prometheus` |
| Loki       | `loki`       |

## Add a dashboard from grafana.com

Exports from grafana.com contain an `__inputs` block with a `${DS_PROMETHEUS}` or `${DS_LOKI}`
placeholder. The Grafana **import wizard** replaces it. **File provisioning does not.** Without the
replacement, the dashboard shows `datasource ${DS_PROMETHEUS} not found`.

`grafana.nix` replaces the placeholders at build time. A `sed` step changes `${DS_PROMETHEUS}` to
`prometheus` and `${DS_LOKI}` to `loki` in each JSON file. You can therefore use a grafana.com
export without changes:

1. Download the dashboard JSON (for example node-exporter-full, grafana.com ID 1860).
2. Save it here as `<name>.json`.
3. Run `git add` on it. Nix flakes do not see untracked files.
4. Deploy. The build replaces the placeholder.

If a dashboard uses a datasource input with a different name, add a `sed` line for it to the
`dashboards` derivation in `grafana.nix`.

## cAdvisor labels

cAdvisor gives each cgroup one label, `id`, with its full path. nspawn cgroups have **no** `name`
label, so all queries use `id`:

| Scope | `id` shape |
|-------|-----------|
| host root | `/` |
| container root (whole container) | `/machine.slice/container@<name>.service` |
| a service inside a container | `/machine.slice/container@<name>.service/payload/**/<svc>.service` |

- To get the container name for the legend, use
  `label_replace(<expr>, "container", "$1", "id", "^.*container@([^/]+)\.service.*$")`.
- To get the service name, use `label_replace(..., "svc", "$1", "id", "^.*/([^/]+)\.service$")`.
- The `$container` variable is `label_values(container_last_seen, id)` with the regex
  `/container@(?<value>[^/]+?)\.service$/`. The final `$` matches container **roots** only. Service
  ids have more path after `.service`.

`machine_cpu_cores` and `machine_memory_bytes` give the host totals for the percent gauges.

### Three cAdvisor traps

Some metrics are not on the `id` of the container root:

- **Network**: cAdvisor reports it on the host root `id="/"`, with `interface="ve-<name>"` (the
  veth of the container). Query
  `container_network_receive_bytes_total{id="/",interface=~"ve-($container)"}` and take the name
  from the `interface` label.
- **Disk**: `container_fs_*` is a total for the device. Each cgroup shows the same value, so it is
  useless per container. Use `container_blkio_device_usage_total` (per cgroup, with
  `operation="Read"` or `"Write"`).
- **CPU**: `container_cpu_usage_seconds_total` has a `cpu="total"` label. Apply `sum by(id)` before
  you divide by `container_spec_cpu_quota/period`, which have only `id`. If you do not, the vector
  match drops all series.
