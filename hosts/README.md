# Host configuration guide

This guide shows how to set up a host (for example `hosts/playground/configuration.nix`). It
covers the global settings and the options of the container services.

## 1. Global settings (`hlamlab.settings`)

The services and Traefik use these settings. Set them in the `configuration.nix` of the host.

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

> **A wrong `lanInterface` cuts SSH.** The firewall opens SSH on that interface only. If the
> confirmation SSH of deploy-rs fails, magic rollback reverts the deploy. Still, check the
> interface name before the first deploy to a new machine.

## 2. Enable and configure services

All services (for example Authelia, Immich, OpenCloud) are off by default. To run a service on a
host, enable it in `hlamlab.services.<name>`.

### Basic example

This enables services with their default limits, IP addresses and storage quotas:

```nix
  hlamlab.services = {
    authelia.enable = true;
    immich.enable = true;
  };
```

### Override limits and networking

Each service has default resource limits and an IP address. You can override any option from the
host, for example to give a heavy service more resources or to change an IP that conflicts:

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

## 3. Advanced configuration

You can also add secrets and change the Traefik routing from the host.

### Secrets

Only the host decrypts secrets. For each secret declared here, the frame declares a host sops
secret (owner root, mode `0400`). nspawn copies it into the container at start, as a systemd
credential, into a read-only file system in RAM. The container has no key, no sops file and no
secret of another service. A change to a secret restarts its whole container.

Use the read-only `path` of a secret, for example `svc.myservice.secrets.myservice-api-key.path`.

*Usually you declare secrets in the service module (`modules/containers/<name>.nix`). You can also
add them from the host.*

```nix
  hlamlab.services.myservice = {
    enable = true;
    
    secrets = {
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

### Network and Traefik overrides

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

## Reference table

This table lists all options under `hlamlab.services.<name>`. The `description` strings in
`modules/containers/frame.nix` are the source of truth.

| Option                  | Type     | Default                   | Description                                                                                                  |
|-------------------------|----------|---------------------------|--------------------------------------------------------------------------------------------------------------|
| **Core**                |          |                           |                                                                                                              |
| `enable`                | `bool`   | `false`                   | Enable the service on this host.                                                                             |
| `containerConfig`       | `module` | *Required*                | NixOS configuration inside the container.                                                                    |
| `privateUsers`          | `enum`   | `"pick"`                  | `"pick"`: own user namespace. Root in the container is an unprivileged host uid. The data dataset is mounted idmapped. Use `"no"` only for a service that needs real host root. |
| **Networking**          |          |                           |                                                                                                              |
| `ip`                    | `str`    | *Required*                | IP address of the container (for example `10.0.0.5`).                                                        |
| `port`                  | `int`    | *Required*                | Service port that Traefik connects to.                                                                       |
| `domainPrefix`          | `str`    | `<name>`                  | Subdomain of the service (for example `'auth'`).                                                             |
| `talksTo`               | `attrs`  | `{}`                      | Other services that this service calls on the private network: `{ <service> = [ <tcp ports> ]; }`. The firewall drops all other traffic. |
| `internet`              | `bool`   | `false`                   | Allow internet access. Private ranges and the home LAN stay blocked.                                         |
| `nameservers`           | `list`   | `[ "1.1.1.1" "1.0.0.1" ]` if `internet`, else `[]` | DNS servers for internet names only. Public names of the other services resolve to the host's Traefik. |
| `traefik.enable`        | `bool`   | `true`                    | Publish this service through Traefik.                                                                        |
| `traefikMiddlewares`    | `list`   | `[ "security-headers" ]`  | Traefik middlewares on the router of this service.                                                           |
| **Derived (read-only)** |          |                           |                                                                                                              |
| `fqdn`                  | `str`    | `<domainPrefix>.<domain>` | Public hostname.                                                                                             |
| `baseUrl`               | `str`    | `https://<fqdn>`          | Public HTTPS base URL.                                                                                       |
| `address`               | `str`    | `<ip>:<port>`             | Internal address of the container.                                                                           |
| **Resources**           |          |                           |                                                                                                              |
| `cpuLimit`              | `str`    | `"100%"`                  | Hard CPU limit (`CPUQuota`).                                                                                 |
| `ramLimit`              | `str`    | `"1G"`                    | Hard RAM limit (`MemoryMax`).                                                                                |
| `ramHigh`               | `str`    | `"512M"`                  | Soft RAM limit (`MemoryHigh`).                                                                               |
| **Storage (ZFS)**       |          |                           |                                                                                                              |
| `zfs.enable`            | `bool`   | `true`                    | Dataset, snapshot schedule and `dataDir` mount for this service.                                             |
| `dataDir`               | `str`    | `/var/lib/<name>`         | Mount point of the state directory in the container. `serviceUser` owns it.                                  |
| `storageQuota`          | `str`    | `"10G"`                   | Maximum size of the ZFS dataset.                                                                             |
| `storageReservation`    | `str`    | `"1G"`                    | Space that ZFS keeps free for the dataset.                                                                   |
| `bindMounts`            | `attrs`  | `{}`                      | Bind mounts in addition to `dataDir`. They are not idmapped, so in a user namespace their files show as `nobody`. |
| **Identity**            |          |                           |                                                                                                              |
| `serviceUser`           | `str`    | `<name>`                  | Name of the service user that the frame creates. It owns `dataDir`.                                          |
| `secrets.<id>.key`      | `str`    | *Required*                | Key path in `secrets.yaml`. `<id>` is the credential id.                                                     |
| `secrets.<id>.unit`     | `str?`   | `null`                    | Unit whose own process reads the file. This unit imports the credential.                                     |
| `secrets.<id>.path`     | `str`    | *read-only*               | Path in the container: `/run/credentials/@system/<id>`, or `/run/credentials/<unit>/<id>`.                   |

Set only the values that differ from these defaults. Do not use `lib.mkDefault`. The service
module is the only place that sets its own values.
