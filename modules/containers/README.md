# Container Services

Each service is self-contained via a single `default.nix` module which defines the container,
Traefik routing, ZFS datasets, and system users via the `hlamlab.services.<name>` submodule
abstraction.

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
{ lib, config, ... }:
{
  hlamlab.services.myservice = {
    # Using lib.mkDefault allows you to easily override these from hosts/<name>/configuration.nix!
    ip = lib.mkDefault "10.0.0.N"; # Check main README.md for next available IP
    port = lib.mkDefault 8080;
    domainPrefix = lib.mkDefault "myservice"; # Will map to https://myservice.yourdomain
    storageQuota = lib.mkDefault "10G";
    storageReservation = lib.mkDefault "1G";
    
    cpuLimit = lib.mkDefault "100%";
    ramLimit = lib.mkDefault "1G";
    ramHigh = lib.mkDefault "512M";
    
    # Optional: Automatically manages sops.secrets inside the container
    secrets = {
      myservice-env = {
        key = "myservice/env";
        restartUnits = [ "myservice.service" ];
      };
    };
    
    # Storage bindings (ZFS datasets are automatically created and snapshotted)
    bindMounts = {
      "/var/lib/myservice" = {
        hostPath = "/var/lib/services/myservice";
        isReadOnly = false;
      };
    };

    # Container-specific NixOS config
    containerConfig = { lib, pkgs, config, ... }: {
      services.myservice = {
        enable = true;
        listenAddress = "0.0.0.0";
        environmentFile = config.sops.secrets.myservice-env.path;
      };
      
      systemd.services.myservice.serviceConfig.StateDirectory = "myservice";
    };
  };
}
```

> The frame opens the service `port` in the container firewall and creates the host state
> directory (`/var/lib/services/<name>`, `0750`) for you — no manual `allowedTCPPorts` for the main
> port or `tmpfiles` rule needed. Only declare `allowedTCPPorts` for *extra* ports (e.g. LDAP `3890`).

### 3. Register and Enable

Add `./myservice.nix` to the imports list in [`modules/containers/default.nix`](default.nix).

To actually enable the service on a specific host, edit the host's configuration (e.g.,
`hosts/playground/configuration.nix`):

```nix
hlamlab.services.myservice = {
  enable = true;
  
  # Because the service definition uses lib.mkDefault, you can override properties here seamlessly!
  # domainPrefix = "override-prefix";
  # storageQuota = "50G";
  # ramLimit = "4G";
  
  # You can also toggle core container-frame features:
  # traefik.enable = false;
  # zfs.enable = false;
  # sanoid.enable = false;
  
  # And you can inject custom NixOS config into the container:
  # extraContainerConfig = { services.nginx.enable = true; };
};
```

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

Limits are defined directly in the service definition (e.g., `myservice.nix`) and can be overridden in
`hosts/.../configuration.nix`.

```nix
  hlamlab.services.myservice = {
    # ...
    cpuLimit = "100%";
    cpuWeight = 100;
    ramLimit = "2G";
    ramHigh = "1.5G";
    memorySwapMax = "0B";
  };
```

**Sizing guide:**

- Light (API/cache): 50% CPU, 512M RAM
- Medium (web/db): 100%, 2G
- Heavy (ML/media): 200%, 4G+

For a full list of overridable options (including IO and TasksMax limits), refer to [`hosts/README.md`](../../hosts/README.md).

---

## Persistent Storage

Use `bindMounts` to map paths to `/var/lib/services/<name>` on the host. ZFS datasets and Sanoid
backup schedules are automatically created by the container frame based on your `storageQuota` and
`storageReservation` settings.

See [ZFS README](../common/zfs/README.md) for dataset creation and snapshot management.
