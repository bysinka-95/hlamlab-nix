# Hlamlab NixOS homelab

A flake-based NixOS configuration for a homelab. The host `playground` is a Proxmox VM. It is the
test bed for the move to the final host.

## Repo layout

- [`flake.nix`](flake.nix): flake inputs, `nixosConfigurations` and the `deploy-rs` targets.
- [`modules/common/`](modules/common): shared defaults (Nix settings, SSH policy, base packages,
  garbage collection) and the `hlamlab.settings` options.
- [`modules/common/network/`](modules/common/network): Traefik, Cloudflare Tunnel, CrowdSec, the
  host firewall, mDNS, the host log agent and the host exporters.
- [`modules/common/zfs/`](modules/common/zfs): ZFS datasets, snapshots and weekly scrubs.
- [`modules/secrets/`](modules/secrets): sops-nix setup and the encrypted `secrets.yaml`.
- [`modules/containers/`](modules/containers): one file per service. Each file uses the
  `hlamlab.services` options from `frame.nix`.
- [`hosts/playground/`](hosts/playground):
    - [`configuration.nix`](hosts/playground/configuration.nix): boot, users and host settings.
      You enable services here.
    - [`disk-config.nix`](hosts/playground/disk-config.nix): the disko ZFS layout for `/dev/sda`
      (GPT, ESP and a ZFS pool).
    - [`hardware-configuration.nix`](hosts/playground/hardware-configuration.nix): the generated
      hardware profile. Generate a new one for each machine.

## Current services

### Network infrastructure

| Service           | Binding        | URL                        | Notes                                                            |
|-------------------|----------------|----------------------------|------------------------------------------------------------------|
| Traefik           | :443           | https://traefik.yourdomain | Dashboard (Authelia 2FA, `admins` group). LE wildcard via DNS-01 |
| Cloudflare Tunnel | (outbound)     | All `*.yourdomain`         | Sends all requests to Traefik :443 and checks its certificate    |
| Host firewall     | nftables       | —                          | LAN: SSH, mDNS, DNS (+ :443 with `lanAddress`). Containers: :443 |
| CrowdSec          | 127.0.0.1:8180 | —                          | LAPI on the host. Reads the Traefik and Authelia logs            |

The LAN can reach SSH, mDNS and DNS (port 53, forwarded to the blocky container). Web traffic from
the internet comes through the tunnel. Traefik's port 443 is open to cloudflared over loopback and
to the containers (hairpin). If `lanAddress` is set, 443 is also open on the LAN (see Blocky below). Only the prometheus
container can reach the metrics ports: 6060, 8080, 8082, 9100 and 60123.

- **Traefik** ([`traefik.nix`](modules/common/network/traefik.nix)) has one `https` entrypoint. It
  gets a Let's Encrypt wildcard certificate through DNS-01 and the Cloudflare API. Logs:
  `/var/log/traefik/traefik.log` and `/var/log/traefik/access.log`.
- **Cloudflare Tunnel** ([`cloudflared.nix`](modules/common/network/cloudflared.nix)) sends
  `*.yourdomain` to `https://localhost:443` and checks Traefik's certificate. sops-nix holds its
  credentials. The [network README](modules/common/network/README.md) explains the setup.

### Application containers

| Service     | IP:Port        | URL                          | Storage path                  | CPU  | RAM (high → max) | ZFS quota / res. |
|-------------|----------------|------------------------------|-------------------------------|------|------------------|------------------|
| opencloud   | 10.0.0.2:9200  | https://opencloud.yourdomain | /var/lib/services/opencloud   | 100% | 1.5G → 2G        | 50G / 10G        |
| immich      | 10.0.0.3:2283  | https://immich.yourdomain    | /var/lib/services/immich      | 200% | 3G → 4G          | 300G / 10G       |
| collabora   | 10.0.0.4:9980  | https://collabora.yourdomain | /var/lib/services/collabora   | 100% | 1G → 1.5G        | 20G / 5G         |
| authelia    | 10.0.0.5:9091  | https://auth.yourdomain      | /var/lib/services/authelia    | 100% | 512M → 1G        | 10G / 1G         |
| lldap       | 10.0.0.6:3000  | https://lldap.yourdomain     | /var/lib/services/lldap       | 100% | 512M → 1G        | 10G / 1G         |
| vaultwarden | 10.0.0.7:8222  | https://vault.yourdomain     | /var/lib/services/vaultwarden | 100% | 512M → 1G        | 10G / 1G         |
| searx       | 10.0.0.8:8888  | https://searxng.yourdomain   | /var/lib/services/searx       | 100% | 512M → 1G        | 10G / 1G         |
| grafana     | 10.0.0.9:3000  | https://grafana.yourdomain   | /var/lib/services/grafana     | 100% | 512M → 768M      | 10G / 1G         |
| prometheus  | 10.0.0.10:9090 | internal only (via Grafana)  | /var/lib/services/prometheus  | 100% | 512M → 1G        | 20G / 2G         |
| loki        | 10.0.0.11:3100 | internal only (via Grafana)  | /var/lib/services/loki        | 100% | 512M → 768M      | 20G / 2G         |
| blocky      | 10.0.0.12:4000 | LAN DNS on the host's :53    | — (no state)                  | 100% | 512M → 1G        | —                |
| gotify      | 10.0.0.13:8080 | https://gotify.yourdomain    | /var/lib/services/gotify      | 100% | 192M → 256M      | 1G / 100M        |
| gatus       | 10.0.0.14:8080 | https://status.yourdomain    | — (history in RAM)            | 100% | 192M → 256M      | —                |
| —           | 10.0.0.15+     | —                            | —                             | —    | —                | —                |

The host gateway uses **10.0.0.1**. The next free IP is **10.0.0.15**.

Each container has its own user namespace. Its root user is an unprivileged uid on the host.

### Observability

`hlamlab.observability.enable` turns on Prometheus (metrics, 30 days), Loki (logs, 30 days) and
Grafana (login through Authelia only).

**Metrics** come from three places:

- The host runs one **node_exporter** (`:9100`, job `node`) for machine CPU, memory, load and disk.
  One copy is enough, because nspawn containers share the host `/proc`.
- The host runs **cAdvisor** (`:8080`). It reads the cgroup tree and is the only source of real
  CPU, memory, network and IO numbers per container.
- Each container runs a **node_exporter** on `:9101` (job `node-container`) with three collectors:
  `systemd`, `filesystem` and `netdev`. These show unit state, dataset usage and network counters
  that the host cannot see.

Prometheus also collects metrics from Traefik, Authelia, cloudflared and CrowdSec.

**Logs**:

- The host **Alloy** agent reads the host journal (with the `container@<name>` units) and the
  Traefik log files.
- Each container runs its **own Alloy** agent. It reads the container's private journal and sends
  it to the host agent on port 3500, with the label `job=<container>`. The host agent forwards all
  logs to Loki. No container can reach Loki, so no container can read the logs of another.
- In Grafana's log viewer, filter by `job`, then by `unit`.
- Both agents use the config in `modules/common/network/alloy-config.nix`.

The host agent accepts the labels that a container sends. A compromised container can therefore
write log lines with the label of a different container. It still cannot read any logs.

### ZFS datasets

| Dataset                   | Mount                         | Quota | Reservation | Compression |
|---------------------------|-------------------------------|-------|-------------|-------------|
| tank/root                 | /                             | —     | —           | lz4         |
| tank/nix                  | /nix                          | —     | —           | lz4         |
| tank/home                 | /home                         | —     | —           | lz4         |
| tank/services             | /var/lib/services             | —     | —           | lz4         |
| tank/services/opencloud   | /var/lib/services/opencloud   | 50G   | 10G         | lz4         |
| tank/services/immich      | /var/lib/services/immich      | 300G  | 10G         | lz4         |
| tank/services/collabora   | /var/lib/services/collabora   | 20G   | 5G          | lz4         |
| tank/services/authelia    | /var/lib/services/authelia    | 10G   | 1G          | lz4         |
| tank/services/lldap       | /var/lib/services/lldap       | 10G   | 1G          | lz4         |
| tank/services/vaultwarden | /var/lib/services/vaultwarden | 10G   | 1G          | lz4         |
| tank/services/searx       | /var/lib/services/searx       | 10G   | 1G          | lz4         |
| tank/services/grafana     | /var/lib/services/grafana     | 10G   | 1G          | lz4         |
| tank/services/prometheus  | /var/lib/services/prometheus  | 20G   | 2G          | lz4         |
| tank/services/loki        | /var/lib/services/loki        | 20G   | 2G          | lz4         |
| tank/backups              | /var/backups                  | —     | —           | gzip        |

The service datasets have `setuid=off`. The [ZFS README](modules/common/zfs/README.md) has the
management and snapshot commands. The [container README](modules/containers/README.md) shows how
to add a service.

## Prerequisites

- Nix with flakes on the build machine.
- SSH access to the target, as root or as the `nixos` user, with your public key on it.
- For a new install: access to the target disk (`/dev/sda` by default) and permission to reboot.
- Two tools, both run from Nix with no install:
    - `nixos-anywhere` for the first install on a bare machine.
    - `deploy-rs` for every deploy after that. It rolls back a deploy that cuts SSH.
- The admin user is `hlamnix` (groups `wheel` and `networkmanager`). Put your own password hash
  into `hashedPassword` in [`configuration.nix`](hosts/playground/configuration.nix). Make the
  hash with `mkpasswd -m sha-512`.

Before the first deploy, put your values into
[`hosts/playground/configuration.nix`](hosts/playground/configuration.nix):

```nix
  hlamlab.settings = {
    domain = "yourdomain.com";           # Your domain name
    tunnelId = "your-tunnel-id-here";    # Your Cloudflare Tunnel ID
    hostId = "your-zfs-host-id";         # Your ZFS host ID (8 hex chars)
  };
```

Do not commit private keys or decrypted credentials.

## Installation

[INSTALLATION.md](INSTALLATION.md) has the full guide: configuration before the install,
nixos-anywhere, the steps after the install, and troubleshooting.

## Deploy

All deploys use **deploy-rs**. Run this from the repo root after you edit the configuration:

```sh
git add -A                            # Nix ignores untracked files, so stage them first
nix run nixpkgs#deploy-rs -- .#playground
```

You need no flags. [`flake.nix`](flake.nix) declares the target hostname, the SSH user, the
activation user, the remote build, the timeouts and the rollback under `deploy`.

### What a deploy does

1. It runs `nix flake check` on the repo.
2. It builds the system **on `playground`** (`remoteBuild = true`). The workstation is
   aarch64-darwin and cannot build x86_64-linux.
3. It connects over SSH as `hlamnix` and activates the new system as `root` through
   passwordless sudo.
4. **Magic rollback**: after the activation, deploy-rs connects again over SSH. If it cannot
   connect within `confirmTimeout`, the host goes back to the previous generation. A plain
   `nixos-rebuild switch` has no such check. A change that breaks sshd, the firewall or the
   network therefore reverts itself and does not lock you out.

### Useful flags

| Flag             | Effect                                                                                       |
|------------------|----------------------------------------------------------------------------------------------|
| `--dry-activate` | Build and copy the system, then show what activation would change. Change nothing            |
| `--test`         | Activate now, but keep the current generation in the bootloader. A reboot goes back to it    |
| `--boot`         | Set the new generation for the next boot. Do not activate it now                             |
| `-i`             | Ask for confirmation before deploy-rs copies anything                                        |
| `-s`             | Skip `nix flake check`. Use it only if you ran the check a moment ago                        |
| `-d`             | Debug logs, for a deploy that stops or fails without a clear error                           |

For a risky change, use this order: `--dry-activate`, then `--test`, then a plain deploy.

### Rollback

Magic rollback acts only when the host becomes unreachable. If the host answers but works badly,
roll it back on the host:

```sh
ssh hlamnix@playground.local
sudo nix-env --profile /nix/var/nix/profiles/system --rollback
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

You can also select an older generation in the GRUB menu at boot. To list the generations, run
`sudo nix-env --profile /nix/var/nix/profiles/system --list-generations`.

### Expected warnings

These warnings are normal:

| Warning                                                      | Meaning                                                                                                    |
|--------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| `unknown flake output 'deploy'`                              | Nix has no schema for the `deploy` attribute of deploy-rs. Cosmetic.                                        |
| `The check omitted these incompatible systems: x86_64-linux` | `nix flake check` on macOS cannot build Linux derivations, so it skips them. A Linux builder runs them.     |
| `Git tree ... is dirty`                                      | You have uncommitted changes. That is fine. Nix does not see **untracked** files, so run `git add -A`.      |

## Upgrading

This repo is a flake. It has no channels and no `nixos-rebuild --upgrade`. `flake.lock` pins
**everything**: the kernel, systemd and each service in the containers. To upgrade, update the lock
file and deploy.

### Packages and services

Update only nixpkgs. This upgrades Immich, Vaultwarden, Grafana, Traefik, the kernel and all other
packages from nixpkgs. disko, sops-nix and deploy-rs stay at their versions.

```sh
nix flake update nixpkgs
git add flake.lock
nix run nixpkgs#deploy-rs -- .#playground --dry-activate   # read the list of restarts first
nix run nixpkgs#deploy-rs -- .#playground
```

`--dry-activate` shows the units that will restart. If a service moves to a new major version,
read its release notes first. nixpkgs does not stop you from running Immich v2 on a v1 database.

### All flake inputs

```sh
nix flake update            # all inputs: nixpkgs, disko, disko-zfs, sops-nix, deploy-rs
git add flake.lock
nix run nixpkgs#deploy-rs -- .#playground
```

This is riskier than a nixpkgs update, because module options change too. To update some inputs
only, name them: `nix flake update disko sops-nix`.

If an update breaks the host, run `git checkout flake.lock` and deploy again. The lock file is the
record of what runs on the host. Commit it together with the change that needs it.

### No automatic upgrades

The host has no `system.autoUpgrade`, for two reasons:

- It would build the last **pushed** commit, not your working copy. Each unpushed deploy would
  then last only until the next automatic run.
- It has no magic rollback. A broken commit would apply with nothing to stop it.

The weekly garbage collection in `modules/common/nix.nix` also deletes old system generations. Do
not expect a generation from some weeks ago to still be there.

## Misc

- **Add a new host**: copy `hosts/playground/` and change the hostname, the disk and the hardware
  configuration. Add the host to `nixosConfigurations` *and* to `deploy.nodes` in `flake.nix`.
  Install it with nixos-anywhere.
- **Disk layout**: GPT on `/dev/sda` with a 1M BIOS boot partition, a 512M ESP and the ZFS pool.
  Edit [`disk-config.nix`](hosts/playground/disk-config.nix) to change it.
- **Secrets**: see [modules/secrets/README.md](modules/secrets/README.md).
- **Check the configuration**: `nix eval .#deploy.nodes.playground.profiles.system.path` evaluates
  the configuration of each container. `nix flake check` alone does not. On the host, read the logs
  with `journalctl -b`.

## Documentation

[DOCS.md](DOCS.md) lists all guides.

| File                                                                 | Contents                                                                             |
|:---------------------------------------------------------------------|:-------------------------------------------------------------------------------------|
| [README.md](README.md)                                               | Repo layout, services (IPs, ports, URLs, ZFS datasets), deploy, upgrade and rollback |
| [INSTALLATION.md](INSTALLATION.md)                                   | New install: configuration, nixos-anywhere, steps after the install, checks          |
| [hosts/README.md](hosts/README.md)                                   | Host settings and all `hlamlab.services` options                                     |
| [modules/common/network/README.md](modules/common/network/README.md) | SSH, mDNS, Traefik, Cloudflare Tunnel, Let's Encrypt, CrowdSec                       |
| [modules/common/zfs/README.md](modules/common/zfs/README.md)         | ZFS datasets, snapshots, backup and replication, commands                            |
| [modules/containers/README.md](modules/containers/README.md)         | Service modules, how to add a service, resource limits, storage                      |
| [modules/secrets/README.md](modules/secrets/README.md)               | sops-nix setup, age keys, secrets and plain settings                                 |
