# Container services

Each service is one `<name>.nix` file. It declares the container, the Traefik route, the ZFS
dataset and the service user through the `hlamlab.services.<name>` options of the frame.

## Structure

```
modules/containers/
├── default.nix           # Imports all service definitions and the container frame
├── frame.nix             # Core abstraction for containerized services
├── <service>.nix         # Complete service definition using hlamlab.services.<name>
├── dashboards/           # Grafana dashboards (see dashboards/README.md)
└── README.md
```

> [**`hosts/README.md`**](../../hosts/README.md) lists all options: resource limits, networking,
> ZFS and the host settings.

All services run in NixOS containers (systemd-nspawn). `frame.nix` creates for each service:

- the ZFS dataset and its Sanoid snapshot schedule,
- the systemd limits of the container,
- the hosts entry and the Traefik route,
- the service user and the data mount,
- the firewall rules and the secrets.

## References to other services

A service often needs the URL or address of another service: an OIDC issuer, a redirect URI, a
datasource, an LDAP backend, a WOPI host, a CSP entry or a scrape target. **Use the derived values
of that service.** Do not write a literal such as `https://auth.${domain}` or `10.0.0.11:3100`.
Each `hlamlab.services.<name>` has three read-only values:

| Value      | Contents                                       | Use for                                                                  |
|------------|------------------------------------------------|--------------------------------------------------------------------------|
| `.fqdn`    | `<domainPrefix>.<settings.domain>` (bare host) | cookie domains, `server_name`, `IDP_DOMAIN`, CSP hosts                   |
| `.baseUrl` | `https://<fqdn>`                               | OIDC issuer and redirect URIs, `externalDomain`, any public URL          |
| `.address` | `<ip>:<port>` (internal)                       | datasource URLs, Prometheus targets, direct calls between containers     |

Bind `svc = config.hlamlab.services;` at the top of the module
(`let svc = config.hlamlab.services; in`). Then use it for the other services:

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

Use `config.hlamlab.settings.domain` directly only for the **whole domain**: wildcard ACL rules
(`*.<domain>`), the session cookie scope, email addresses. Do not use it for the host of one
service.

## Add a service

### 1. Update `README.md`

Add the service to the **Application containers** table in the main
[`README.md`](../../README.md). Give it a free IP and write down its storage quota.

### 2. Create the module

Create `modules/containers/<name>.nix`:

```nix
{ config, ... }:
let
  svc = config.hlamlab.services;
in
{
  hlamlab.services.myservice = {
    ip = "10.0.0.N"; # Check main README.md for the next available IP
    port = 8080;

    # Set only what differs from the frame's defaults (see hosts/README.md).
    # No lib.mkDefault: this module is the only place that sets these values.
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

The frame does the rest:

- **Storage.** It creates the ZFS dataset, the snapshot schedule and the host directory. It mounts
  the dataset on `dataDir` (`/var/lib/myservice` by default), owned by `serviceUser`. You need no
  `bindMounts` entry, no `tmpfiles` rule and no `StateDirectory=` for ownership. Change `dataDir`
  only if the upstream module needs a different path. Collabora needs `/var/lib/cool`.
- **Container firewall.** It opens the service `port` in the container. Use `allowedTCPPorts`
  only for *extra* ports, for example LDAP `3890`.
- **Host firewall.** It drops traffic between containers unless the source declares it in
  `talksTo`. It drops internet traffic unless the service sets `internet = true`. A missing flow
  shows in the kernel log as `hlamlab-forward-drop:` (`journalctl -k | grep hlamlab-forward-drop`).
  Declare the flow in `talksTo`. Do not change the firewall by hand. The frame itself allows
  Prometheus to collect the container exporters (:9101).
- **User namespace.** Each container has its own user namespace. Root in the container is an
  unprivileged uid range on the host (`machinectl show <name>`, `/proc/<leader>/uid_map`). The
  root file system and the data dataset are mounted idmapped, so files keep their owners on disk
  and nothing is chowned. Set `privateUsers = "no"` only for a service that needs real host root.
- **Secrets.** Secrets come in as systemd credentials. Only the host decrypts them. The container
  gets only its own secrets, in RAM. Use `svc.<name>.secrets.<id>.path`. Set `unit` only when the
  non-root process of the service reads the file (a `*_file` setting, `$__file{}`). Root reads
  `EnvironmentFile=`, `LoadCredential=` and the `*File` options of NixOS modules, so these need no
  `unit`. A change to a secret restarts the whole container.

### 3. Register and enable

Add `./myservice.nix` to the imports in [`modules/containers/default.nix`](default.nix).

To run the service on a host, enable it in the host configuration (for example
`hosts/playground/configuration.nix`):

```nix
hlamlab.services.myservice.enable = true;
```

The host can override any other value, but no host does this now. The service module sets its own
values. [`hosts/README.md`](../../hosts/README.md) has the full option table.

---

## Container operations

```bash
machinectl list                                           # list containers
sudo nixos-container root-login <name>                    # shell into container
systemctl status container@<name>                         # status
sudo nixos-container run <name> -- journalctl -u <svc> -f # live logs
sudo nixos-container start <name>                         # start (stop works the same way)
```

---

## Current services

The [main README](../../README.md#current-services) lists the IPs, ports, URLs, storage, resource
limits and ZFS datasets.

## Authelia

`modules/containers/authelia.nix` declares the OIDC clients and the access rules. Users and
groups are in LLDAP. A deploy applies the changes.

---

## Resource limits

Set the limits in the service module (for example `myservice.nix`). The frame applies them to
`container@<name>.service` as `CPUQuota`, `MemoryMax` and `MemoryHigh`. Each container also gets
`MemorySwapMax=0B` and `TasksMax=512`.

```nix
  hlamlab.services.myservice = {
    # ...
    cpuLimit = "200%";
    ramLimit = "2G";
    ramHigh = "1.5G";
  };
```

**Sizes:**

- Light (API, cache): 50% CPU, 512M RAM.
- Medium (web app): 100% CPU, 1G RAM. These are the defaults.
- Heavy (ML, media): 200% CPU, 4G RAM or more.

---

## Persistent storage

The frame creates the ZFS dataset and its Sanoid snapshot schedule. `storageQuota` and
`storageReservation` set the size. The frame mounts `/var/lib/services/<name>` on `dataDir` in the
container, owned by `serviceUser`. Use `bindMounts` only for other paths. These bind mounts are not
idmapped, so in a user namespace their files show as `nobody`.

The datasets have `setuid=off`. Root in the container writes to the data mount as host uid 0. With
`setuid=off`, the kernel ignores setuid bits on these files. A setuid file that a container
leaves there cannot give root on the host.

The [ZFS README](../common/zfs/README.md) explains datasets and snapshots.

### PostgreSQL: collation version mismatch

After a nixpkgs update with a new glibc, PostgreSQL in a container logs this warning every
30 seconds:

```
WARNING:  database "immich" has a collation version mismatch
DETAIL:  The database was created using collation version 2.42, but the operating system provides version 2.44.
```

Text indexes that use the old sort order can give wrong results. Rebuild them, then record the new
version. Do this for each database in the container (`immich`, `postgres`, `template1`):

```bash
sudo nixos-container run immich -- su postgres -c \
  "psql -d immich -c 'REINDEX DATABASE immich' -c 'ALTER DATABASE immich REFRESH COLLATION VERSION'"
```

`REINDEX` locks each table for a short time. On a large database, do it when nobody uses the
service.

### OpenCloud: config after a major upgrade

The module runs `opencloud init` only when `/etc/opencloud/opencloud.yaml` does not exist. A new
major version can need new keys in that file (9.x needs `auth_guest.service_account`). Without
them, the new service uses defaults and its feature does not work. After a major upgrade, read the
upstream upgrade guide, then add the missing keys:

```bash
sudo nixos-container root-login opencloud
OC=$(systemctl show opencloud -p ExecStart --value | grep -o '/nix/store/[^ ]*/bin/opencloud' | head -1)
cd /etc/opencloud && cp -a opencloud.yaml /root/opencloud.yaml.bak
$OC init --diff --insecure false --config-path /etc/opencloud   # writes opencloud.config.patch
patch opencloud.yaml < opencloud.config.patch
rm opencloud.config.patch opencloud.yaml.*.backup
systemctl restart opencloud
```

The patch file contains secrets. Do not copy it out of the container.
