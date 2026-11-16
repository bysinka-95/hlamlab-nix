# Container Services

Each service is one flat `<name>.nix` file defining the container, Traefik routing, ZFS dataset,
and system user through the `hlamlab.services.<name>` submodule the frame provides.

## Structure

```
modules/containers/
├── default.nix           # Imports all service definitions and the container frame
├── frame.nix             # Core abstraction for containerized services
├── <service>.nix         # Complete service definition using hlamlab.services.<name>
└── README.md
```

> **Note**: For a full reference of available options (like resource limits, networking, ZFS settings, and host-specific options), see [**`hosts/README.md`**](../../hosts/README.md).

---

# Container Service Modules

All services run in native NixOS containers, isolated from the host.

## Service Anatomy

Each service resides in a dedicated file (e.g., `modules/containers/myservice.nix`) and leverages the
`frame.nix` abstraction. This frame automatically handles ZFS datasets, Sanoid snapshots,
systemd limits, DNS, Traefik routing, and users based on a simple set of attributes.

## Cross-service references — never hardcode another service's prefix, IP, or port

When one service needs another's URL or address (OIDC issuer, redirect URI, datasource, LDAP
backend, WOPI host, CSP entry, scrape target…), **reference the target service's derived handles**
instead of writing a literal like `https://auth.${domain}` or `10.0.0.11:3100`. The frame exposes
three read-only handles on every `hlamlab.services.<name>`:

| Handle     | Value                                          | Use for                                                                  |
|------------|------------------------------------------------|--------------------------------------------------------------------------|
| `.fqdn`    | `<domainPrefix>.<settings.domain>` (bare host) | cookie domains, `server_name`, `IDP_DOMAIN`, CSP hosts                   |
| `.baseUrl` | `https://<fqdn>`                               | OIDC issuer/redirect URIs, `externalDomain`, any public URL              |
| `.address` | `<ip>:<port>` (internal)                       | datasource URLs, Prometheus targets, direct container-to-container calls |

Bind `svc = config.hlamlab.services;` at the top of the module (`let svc = config.hlamlab.services; in`)
and reference siblings through it:

```nix
# ✅ follows a prefix/IP change automatically
issuerUrl = svc.authelia.baseUrl;                    # https://auth.<domain>
IDP_DOMAIN = svc.authelia.fqdn;                      # auth.<domain>
url = "http://${svc.prometheus.address}";            # http://10.0.0.10:9090
redirect_uris = [ "${svc.grafana.baseUrl}/login/generic_oauth" ];

# ❌ breaks the moment someone changes authelia's domainPrefix or prometheus's ip
issuerUrl = "https://auth.${config.hlamlab.settings.domain}";
url = "http://10.0.0.10:9090";
```

Only use `config.hlamlab.settings.domain` directly for the **whole domain** itself (wildcard ACL
rules `*.<domain>`, session cookie scope, email addresses) — not for a specific service's host.

## Adding a Service

**Follow these 3 steps:**

### 1. Update `README.md`

Add the new service to the **Application Containers** table in the main [
`README.md`](../../README.md). Assign an available IP and note the required storage quota.

### 2. Create the Module

In `modules/containers/`, create `<name>.nix`.

**`<name>.nix`** (App configuration):

```nix
{ config, ... }:
let
  svc = config.hlamlab.services;
in
{
  hlamlab.services.myservice = {
    ip = "10.0.0.N"; # Check main README.md for the next available IP
    port = 8080;

    # Set only what differs from the frame's defaults. domainPrefix, nameservers,
    # storageQuota/Reservation, cpuLimit, ramLimit/High all have sane ones — see
    # hosts/README.md. No lib.mkDefault: this module is their only definer.
    storageQuota = "50G";

    # Network: every container-to-container flow is dropped unless declared.
    # List only siblings you call directly on the private network (ip:port);
    # calls by public URL go through the host's Traefik and need nothing.
    talksTo.postgres = [ 5432 ];
    # Internet egress (never the home LAN). Without it the container has no
    # resolvers, so stray lookups fail at once.
    internet = true;

    # Optional: secrets from secrets.yaml, handed in as credentials (host decrypts)
    secrets = {
      myservice-env = {
        key = "myservice/env";
        # unit = "myservice.service"; # only if the service's own process reads the file
      };
    };

    # Container-specific NixOS config
    containerConfig = { ... }: {
      services.myservice = {
        enable = true;
        listenAddress = "0.0.0.0";
        port = svc.myservice.port;
        environmentFile = svc.myservice.secrets.myservice-env.path;
      };
    };
  };
}
```

> The frame gives you the ZFS dataset, its snapshot schedule, the host state directory, and the
> bind mount onto `dataDir` (`/var/lib/myservice` by default) chowned to `serviceUser` — so no
> `bindMounts` entry, no `tmpfiles` rule, and no `StateDirectory=` added just to fix ownership.
> It also opens the service `port` in the container firewall; declare `allowedTCPPorts` only for
> *extra* ports (e.g. LDAP `3890`). Override `dataDir` only when the upstream module insists on
> another path — collabora wants `/var/lib/cool`.
>
> The host firewall drops traffic between containers unless the source declares it in `talksTo`,
> and internet egress unless it sets `internet = true`. A missing flow shows up in the journal as
> `hlamlab-forward-drop:` (`journalctl -k | grep hlamlab-forward-drop`) — declare it there; never
> widen the firewall by hand. Prometheus' scrape of the frame's per-container exporters (:9101) is
> allowed by the frame itself.
>
> Every container gets its own user namespace: root inside is an
> unprivileged uid range on the host (`machinectl show <name>` / `/proc/<leader>/uid_map`). The
> root filesystem and the data dataset are mounted idmapped, so files keep their on-disk owners
> and nothing is chowned. `privateUsers = "no"` opts out, for a service that needs real host root.
>
> Secrets arrive as systemd credentials: only the host decrypts, and the container gets just its
> own, in RAM. Reference them through `svc.<name>.secrets.<id>.path`. Set `unit` only when the
> service's own non-root process reads the file (a `*_file` setting, `$__file{}`); root-read paths
> (`EnvironmentFile=`, `LoadCredential=`, the NixOS modules' `*File` options) need none. Changing a
> secret restarts the whole container.

### 3. Register and Enable

Add `./myservice.nix` to the imports list in [`modules/containers/default.nix`](default.nix).

To actually enable the service on a specific host, edit the host's configuration (e.g.,
`hosts/playground/configuration.nix`):

```nix
hlamlab.services.myservice.enable = true;
```

Host-level overrides of anything else are possible but unused today — the service module owns its
own values. See [`hosts/README.md`](../../hosts/README.md) for the full option table.

---

## Container Operations

```bash
machinectl list                                           # list containers
sudo nixos-container root-login <name>                    # shell into container
systemctl status container@<name>                         # status
sudo nixos-container run <name> -- journalctl -u <svc> -f # live logs
```

---

## Current Services

See [main README](../../README.md#current-services) — IPs, ports, URLs, storage, resource limits,
ZFS datasets.

## Authelia Declarative Provisioning

Manage Authelia users, groups, and OAuth2 systems in `modules/containers/authelia.nix`.
Changes are applied automatically on deploy.

---

## Container Management

```bash
machinectl list                                           # list containers
sudo nixos-container root-login <name>                    # shell into container
systemctl status container@<name>                         # status
sudo nixos-container run <name> -- journalctl -u <svc> -f # live logs
sudo nixos-container start/stop <name>
```

---

## Resource Limits

Limits are defined in the service definition (e.g., `myservice.nix`) and applied by the frame to
`container@<name>.service` as `CPUQuota` / `MemoryMax` / `MemoryHigh`. Every container also gets a
fixed `MemorySwapMax=0B` and `TasksMax=512`.

```nix
  hlamlab.services.myservice = {
    # ...
    cpuLimit = "200%";
    ramLimit = "2G";
    ramHigh = "1.5G";
  };
```

**Sizing guide:**

- Light (API/cache): 50% CPU, 512M RAM
- Medium (web/db): 100%, 2G — the defaults
- Heavy (ML/media): 200%, 4G+

---

## Persistent Storage

The frame creates the ZFS dataset, its Sanoid snapshot schedule (sized by `storageQuota` /
`storageReservation`), and bind-mounts `/var/lib/services/<name>` onto `dataDir` inside the
container, chowned to `serviceUser`. Use `bindMounts` only for paths *beyond* that one.

See [ZFS README](../common/zfs/README.md) for dataset creation and snapshot management.
