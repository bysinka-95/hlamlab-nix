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

## Recommended starters

- **1860** node-exporter-full — host + per-container metrics.
- **13639** Loki logs / quick search.
- **17346** Traefik official.
