# Host Configuration Guide

This document explains how to set up your hosts (like `hosts/playground/configuration.nix`), how to
configure global environment settings, and how to declare, configure, and extend containerized
services.

## 1. Global Settings (`hlamlab.settings`)

Global settings define the cluster-wide environment that your services and Traefik router rely on.
These must be defined in your host's `configuration.nix`.

```nix
  hlamlab.settings = {
    # The base domain used for all Traefik routing (e.g. auth.yourdomain.com)
    domain = "yourdomain.com";
    
    # Your Cloudflare Tunnel ID (must match the credentials file in secrets)
    tunnelId = "00000000-0000-0000-0000-000000000000f";
    
    # ZFS host ID (obtain by running `head -c 8 /etc/machine-id`)
    hostId = "1a23bc45";

    # Optional: Customize the LDAP Base DN. 
    # If not set, it defaults to a domain-derived value (e.g. dc=yourdomain,dc=com)
    # ldapBaseDn = "dc=custom,dc=local";

    # The host's LAN NIC (`ip -br link`). Defaults to "ens18" (Proxmox virtio).
    # Container egress leaves through it, and it is the only interface SSH and
    # mDNS answer on.
    # lanInterface = "enp1s0";
  };
```

> **A wrong `lanInterface` cuts SSH.** The firewall opens SSH on that interface only. deploy-rs'
> magic rollback reverts such a deploy when its confirmation SSH fails, but check the NIC name
> before the first deploy to a new machine.

## 2. Enabling and Configuring Services

All services (like Authelia, Immich, OpenCloud) are disabled by default. You opt-in to running them
on a specific host by enabling them in `hlamlab.services.<name>`.

### Basic Example

To simply enable a service with its default resource limits, IP address, and storage quotas:

```nix
  hlamlab.services = {
    authelia.enable = true;
    immich.enable = true;
  };
```

### Overriding Resource Limits & Networking

Every service comes with sensible default resource limits and network IP addresses. If you need to
scale up a heavy service or change its IP to avoid conflicts on a new host, you can easily override
any property:

```nix
  hlamlab.services.immich = {
    enable = true;
    
    # --- Networking ---
    # Assign a custom static IP for the container's virtual ethernet
    ip = "10.0.0.99";
    # By default, Immich might use "immich". This maps to https://photos.yourdomain.com
    domainPrefix = "photos"; 

    # --- Resource Limits ---
    # Give Immich more CPU and RAM for machine learning tasks
    cpuLimit = "400%";
    ramLimit = "8G";
    ramHigh = "6G";
    
    # --- Storage ---
    # Increase the ZFS dataset quota for photos
    storageQuota = "1T";
  };
```

## 3. Advanced Configuration

Beyond the per-service defaults, you can map custom secrets and alter Traefik routing from the host.

### Managing Secrets

Only the host decrypts. For every secret declared here the frame declares a host sops secret
(root, `0400`) and hands it to the container as a systemd credential: nspawn copies it in at
container start, into a RAM-only read-only filesystem. The container never holds a key, a sops
file or another service's secret. Changing a secret restarts its whole container.

Reference a secret through its read-only `path`, e.g. `svc.myservice.secrets.myservice-api-key.path`.

*Note: You usually declare these inside the service definition (`modules/containers/<name>.nix`),
but you can extend them from the host.*

```nix
  hlamlab.services.myservice = {
    enable = true;
    
    secrets = {
      # The attribute name is arbitrary, but conventionally represents the secret's purpose
      # The attribute name is the credential id (no `/`)
      myservice-api-key = {
        # The key path in your secrets.yaml file
        key = "myservice/api-key";
        # Only when the service's own (non-root) process reads the file, e.g.
        # a `*_file` setting. Leave unset for EnvironmentFile=, LoadCredential=
        # and the NixOS modules' `*File` options — root reads those.
        unit = "myservice-backend.service";
      };
    };
  };
```

### Network and Traefik Overrides

```nix
  hlamlab.services.customapp = {
    enable = true;

    # Skip Traefik entirely — internal-only services (prometheus, loki) do this.
    traefik.enable = false;

    # Replaces the default [ "security-headers" ] (collabora swaps in its own).
    traefikMiddlewares = [ "collabora-headers" ];

    # Only when the upstream NixOS module insists on a path of its own; the
    # ZFS-backed state directory is bind-mounted here and chowned to serviceUser.
    dataDir = "/var/lib/cool";
    serviceUser = "cool";
  };
```

## Complete Reference Table

Every option under `hlamlab.services.<name>`. The `description` strings in
`modules/containers/frame.nix` are the source of truth; this table mirrors them.

| Option                  | Type     | Default                   | Description                                                                                                  |
|-------------------------|----------|---------------------------|--------------------------------------------------------------------------------------------------------------|
| **Core**                |          |                           |                                                                                                              |
| `enable`                | `bool`   | `false`                   | Enable the service on this host.                                                                             |
| `containerConfig`       | `module` | *Required*                | NixOS configuration for inside the container.                                                                |
| **Networking**          |          |                           |                                                                                                              |
| `ip`                    | `str`    | *Required*                | Container local IP address (e.g., `10.0.0.5`).                                                               |
| `port`                  | `int`    | *Required*                | Container service port exposed to Traefik.                                                                   |
| `domainPrefix`          | `str`    | `<name>`                  | Prefix for the domain routing (e.g., `'auth'`).                                                              |
| `talksTo`               | `attrs`  | `{}`                      | Siblings this service calls on the private network: `{ <service> = [ <tcp ports> ]; }`. All else dropped.  |
| `internet`              | `bool`   | `false`                   | Allow internet egress (private ranges / the home LAN stay unreachable).                                     |
| `nameservers`           | `list`   | `[ "1.1.1.1" "1.0.0.1" ]` if `internet`, else `[]` | Resolvers for internet egress only; sibling services' public names map to the host's Traefik. |
| `traefik.enable`        | `bool`   | `true`                    | Publish this service through Traefik.                                                                        |
| `traefikMiddlewares`    | `list`   | `[ "security-headers" ]`  | Traefik middlewares applied to this service's router.                                                        |
| **Derived (read-only)** |          |                           |                                                                                                              |
| `fqdn`                  | `str`    | `<domainPrefix>.<domain>` | Public hostname.                                                                                             |
| `baseUrl`               | `str`    | `https://<fqdn>`          | Public HTTPS base URL.                                                                                       |
| `address`               | `str`    | `<ip>:<port>`             | Internal container address.                                                                                  |
| **Resources**           |          |                           |                                                                                                              |
| `cpuLimit`              | `str`    | `"100%"`                  | Hard CPU limit (`CPUQuota`).                                                                                 |
| `ramLimit`              | `str`    | `"1G"`                    | Hard RAM limit (`MemoryMax`).                                                                                |
| `ramHigh`               | `str`    | `"512M"`                  | Soft RAM limit (`MemoryHigh`).                                                                               |
| **Storage (ZFS)**       |          |                           |                                                                                                              |
| `zfs.enable`            | `bool`   | `true`                    | Dataset, snapshot schedule and `dataDir` bind mount for this service.                                        |
| `dataDir`               | `str`    | `/var/lib/<name>`         | Where the state directory is mounted inside the container, chowned to `serviceUser`.                         |
| `storageQuota`          | `str`    | `"10G"`                   | ZFS dataset maximum quota.                                                                                   |
| `storageReservation`    | `str`    | `"1G"`                    | ZFS dataset guaranteed reservation.                                                                          |
| `bindMounts`            | `attrs`  | `{}`                      | Bind mounts beyond the automatic `dataDir`.                                                                  |
| **Identity**            |          |                           |                                                                                                              |
| `serviceUser`           | `str`    | `<name>`                  | Name of the auto-created service user; owns `dataDir`.                                                       |
| `secrets.<id>.key`      | `str`    | *Required*                | Key path in `secrets.yaml`; `<id>` is the credential id.                                                     |
| `secrets.<id>.unit`     | `str?`   | `null`                    | Unit whose own process reads the file; it imports the credential.                                            |
| `secrets.<id>.path`     | `str`    | *read-only*               | Path inside the container: `/run/credentials/@system/<id>`, or `/run/credentials/<unit>/<id>`.               |

Set only what differs from these defaults, and without `lib.mkDefault` — a service module is the
only place its own values are ever set.
