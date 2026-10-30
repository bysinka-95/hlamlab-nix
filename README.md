# Hlamlab NixOS homelab

Flake-based NixOS configuration for the homelab. `playground` is the current Proxmox VM target used
to iterate toward
the eventual host migration.

## Repo layout

- [`flake.nix`](flake.nix): Flake inputs, `nixosConfigurations`, and `deploy-rs` targets.
- [`modules/common/`](modules/common): Shared defaults (nix settings, allowUnfree, SSH policy, base
  packages, GC, auto-upgrades) and settings definitions.
- [`modules/common/network/`](modules/common/network): Network services (Traefik reverse proxy with
  usersFile auth, Cloudflare Tunnel, mDNS).
- [`modules/common/zfs/`](modules/common/zfs): ZFS configuration (declarative datasets, snapshots,
  weekly scrubbing).
- [`modules/secrets/`](modules/secrets): sops-nix configuration and encrypted secrets. Only secret
  keys live inside `secrets.yaml`.
- [`modules/containers/`](modules/containers): Flat service configuration files using the
  `hlamlab.services` container `frame.nix`.
- [`hosts/playground/`](hosts/playground)
    - [`configuration.nix`](hosts/playground/configuration.nix): System config (boot, networking,
      users). This is where services are explicitly enabled.
    - [`disk-config.nix`](hosts/playground/disk-config.nix): Disko ZFS layout for `/dev/sda` (GPT +
      ESP + ZFS pool).
    - [`hardware-configuration.nix`](hosts/playground/hardware-configuration.nix): Generated
      hardware profile; replace/regenerate per machine.

## Current Services

### Network Infrastructure

| Service           | Binding    | URL                        | Notes                                           |
|-------------------|------------|----------------------------|-------------------------------------------------|
| Traefik           | :443       | https://traefik.yourdomain | Dashboard (basic auth); LE wildcard via DNS-01  |
| Cloudflare Tunnel | (outbound) | Covers all `*.yourdomain`  | Routes → Traefik :443 (TLS verified)            |
| Host firewall     | nftables   | —                          | LAN: SSH + mDNS only. Containers: Traefik :443  |

The LAN reaches nothing but SSH and mDNS: services are reached through the tunnel. Traefik's :443
is open to the containers (hairpin) and to cloudflared over loopback; the metrics ports
(8080, 8082, 9100, 60123) to the prometheus container only.

- **Traefik** — [`modules/common/network/traefik.nix`](modules/common/network/traefik.nix):
  the `https` entrypoint with a Let's Encrypt wildcard (DNS-01 through the Cloudflare API), shared
  `security-headers` middleware, dashboard router.
  Logs: `/var/log/traefik/traefik.log` and `/var/log/traefik/access.log`.
- **Cloudflare Tunnel** — [
  `modules/common/network/cloudflared.nix`](modules/common/network/cloudflared.nix): routes all
  `*.yourdomain` → `https://localhost:443`, verifying Traefik's certificate. Credentials managed
  via sops-nix. See [Network README](modules/common/network/README.md) for the certificate setup.

### Application Containers

| Service     | IP:Port        | URL                          | Storage Path                  | CPU  | RAM (high → max) | ZFS Quota / Res |
|-------------|----------------|------------------------------|-------------------------------|------|------------------|-----------------|
| opencloud   | 10.0.0.2:9200  | https://opencloud.yourdomain | /var/lib/services/opencloud   | 100% | 1.5G → 2G        | 50G / 10G       |
| immich      | 10.0.0.3:2283  | https://immich.yourdomain    | /var/lib/services/immich      | 200% | 3G → 4G          | 300G / 10G      |
| collabora   | 10.0.0.4:9980  | https://collabora.yourdomain | /var/lib/services/collabora   | 100% | 1G → 1.5G        | 20G / 5G        |
| authelia    | 10.0.0.5:9091  | https://auth.yourdomain      | /var/lib/services/authelia    | 100% | 512M → 1G        | 10G / 1G        |
| lldap       | 10.0.0.6:3000  | https://lldap.yourdomain     | /var/lib/services/lldap       | 100% | 512M → 1G        | 10G / 1G        |
| vaultwarden | 10.0.0.7:8222  | https://vault.yourdomain     | /var/lib/services/vaultwarden | 100% | 512M → 1G        | 10G / 1G        |
| searx       | 10.0.0.8:8888  | https://searxng.yourdomain   | /var/lib/services/searx       | 100% | 512M → 1G        | 10G / 1G        |
| grafana     | 10.0.0.9:3000  | https://grafana.yourdomain   | /var/lib/services/grafana     | 100% | 512M → 768M      | 10G / 1G        |
| prometheus  | 10.0.0.10:9090 | internal only (via Grafana)  | /var/lib/services/prometheus  | 100% | 512M → 1G        | 20G / 2G        |
| loki        | 10.0.0.11:3100 | internal only (via Grafana)  | /var/lib/services/loki        | 100% | 256M → 512M      | 20G / 2G        |
| —           | 10.0.0.12+     | —                            | —                             | —    | —                | —               |

**IP 10.0.0.1** is reserved for the host gateway. **Next available:** 10.0.0.12.

**Observability** — Prometheus (metrics, 30d) + Loki (logs, 30d) + Grafana (OIDC via
Authelia only), enabled by `hlamlab.observability.enable`.

- **Metrics** are pulled from three sources. On the host (`modules/common/network/exporters.nix`):
  **node_exporter** (`:9100`, job `node`) for machine
  CPU/mem/load/disk — collected once, since nspawn shares the host `/proc` — and **cAdvisor**
  (`:8080`) reading the cgroup tree, the only source of real per-container CPU/mem/net/IO. Inside
  each container (`frame.nix`): a **node_exporter** on `:9101` (job `node-container`) cut down with
  `--collector.disable-defaults` to `systemd`, `filesystem` and `netdev` — the three collectors
  that *are* namespaced, giving per-service systemd unit state, ZFS dataset usage and netns
  counters that nothing on the host can see. Traefik, Authelia, and cloudflared are scraped too.
- **Logs** — a host-level **Alloy** captures the host journal (incl. `container@<name>` spawn
  wrappers) and Traefik's files. Each container additionally runs its **own Alloy** that ships
  its private journal — the real service logs (`immich-server.service` &c.) that nspawn never
  surfaces to the host — to Loki, labelled `job=<container>`. Filter by that job then `unit` in
  Grafana's Log Viewer. Both agents render the same river config from
  `modules/common/network/alloy-config.nix`.

### ZFS Datasets

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

For ZFS management commands, snapshot operations, and adding new datasets, see
[ZFS Module Documentation](modules/common/zfs/README.md).
For container management commands and how to add new services, see
[Container Module Documentation](modules/containers/README.md).

## Prerequisites

- Nix with flakes enabled on the build machine.
- SSH reachability to the target (root or nixos user) and your SSH public key present on the target.
- For fresh installs: access to the target disk (`/dev/sda` assumed) and ability to reboot.
- Tools (run straight from Nix, nothing to install):
    - `nixos-anywhere` — first install onto a bare machine.
    - `deploy-rs` — every deploy after that. Auto-rollback included.
- Default admin user: `hlamnix` (wheel/networkmanager). Set its hashed password in [
  `hosts/playground/configuration.nix`](hosts/playground/configuration.nix)
  by replacing `<replace-with-mkpasswd-sha-512>` with the output of `mkpasswd -m sha-512`.

Before deploying, edit the host configuration file with your host's values:

**Edit [`hosts/playground/configuration.nix`](hosts/playground/configuration.nix)**:

```nix
  hlamlab.settings = {
    domain = "yourdomain.com";           # Your domain name
    tunnelId = "your-tunnel-id-here";    # Your Cloudflare Tunnel ID
    hostId = "your-zfs-host-id";         # Your ZFS host ID (8 hex chars)
  };
```

**Note**: Do not commit actual private keys or decrypted credentials.

## Installation

See **[INSTALLATION.md](INSTALLATION.md)** for the complete guide (pre-install config,
nixos-anywhere, post-install
steps, and troubleshooting).

## Deploy

Deploys go through **deploy-rs**. Run from the repo root after editing configs:

```sh
git add -A                            # Nix ignores untracked files — stage first
nix run nixpkgs#deploy-rs -- .#playground
```

That is the whole command. Everything it needs — target hostname, SSH user, activation user,
remote build, timeouts, rollback — is declared in [`flake.nix`](flake.nix) under `deploy`, not
passed on the command line.

### What it does

1. Runs `nix flake check` on the repo.
2. Builds the system closure **on `playground` itself** (`remoteBuild = true`) — the workstation
   is aarch64-darwin and cannot build x86_64-linux.
3. SSHes in as `hlamnix`, activates the profile as `root` via passwordless sudo.
4. **Magic rollback**: after activation it reconnects over SSH to confirm the host is still
   reachable. No confirmation within `confirmTimeout` → the host rolls itself back automatically.
   This is the safety net a plain `nixos-rebuild switch` does not have: a change that breaks
   sshd, the firewall, or networking undoes itself instead of locking you out.

### Useful flags

| Flag             | Effect                                                                                                  |
|------------------|---------------------------------------------------------------------------------------------------------|
| `--dry-activate` | Build and push the closure, print what activation *would* change, change nothing                        |
| `--test`         | Activate now, but leave the bootloader pointing at the current generation (reboot = back to known-good) |
| `--boot`         | Opposite: stage for next boot without activating now                                                    |
| `-i`             | Confirm interactively before anything is pushed                                                         |
| `-s`             | Skip the `nix flake check` pre-flight (faster iteration; only when you just ran it)                     |
| `-d`             | Debug logs, when a deploy hangs or fails opaquely                                                       |

Safe escalation for a risky change: `--dry-activate` → `--test` → plain deploy.

### Rollback

Magic rollback covers *unreachable*. For a host that is reachable but misbehaving, roll back
on the host:

```sh
ssh hlamnix@playground.local
sudo nix-env --profile /nix/var/nix/profiles/system --rollback
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

Or pick an older generation from the GRUB menu at boot. List them with
`sudo nix-env --profile /nix/var/nix/profiles/system --list-generations`.

### Expected warnings

These are normal and not a problem:

| Warning                                                      | Meaning                                                                                                                           |
|--------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| `unknown flake output 'deploy'`                              | Nix has no schema for deploy-rs' `deploy` attribute. Cosmetic.                                                                    |
| `The check omitted these incompatible systems: x86_64-linux` | `nix flake check` on macOS cannot realise Linux derivations, so it skips the deploy checks. They run on a Linux builder or in CI. |
| `Git tree ... is dirty`                                      | You have uncommitted changes. Fine — but **untracked** files are invisible to Nix, hence the `git add -A` above.                  |

## Upgrading

This repo is a flake, so there is no `nixos-rebuild --upgrade` and no channels. **Everything —
kernel, systemd, and every containerised service — is pinned by `flake.lock`.** Upgrading means
moving that lock, then deploying.

### Packages and services (the common case)

Bump nixpkgs only. That upgrades Immich, Vaultwarden, Grafana, Traefik, the kernel — everything
that comes from nixpkgs — while leaving disko/sops-nix/deploy-rs where they are:

```sh
nix flake update nixpkgs
git add flake.lock
nix run nixpkgs#deploy-rs -- .#playground --dry-activate   # look before you leap
nix run nixpkgs#deploy-rs -- .#playground
```

`--dry-activate` lists which units will restart. If a service jumped a major version, check its
release notes first — nixpkgs will happily hand you Immich v2 on a v1 database.

### Everything (flake inputs)

```sh
nix flake update            # all inputs: nixpkgs, disko, disko-zfs, sops-nix, deploy-rs
git add flake.lock
nix run nixpkgs#deploy-rs -- .#playground
```

Riskier than the above — module interfaces move, not just package versions. Individual inputs:
`nix flake update disko sops-nix`.

Roll back a bad update with `git checkout flake.lock` and redeploy. The lock file is the record
of what is running; commit it with the change that caused it.

### Automatic upgrades — off, and why

`modules/common/nix.nix` declares `system.autoUpgrade` but leaves it **disabled**. Enabling it
would have the host pull `github:bysinka-95/hlamlab-nix#playground` nightly at 04:00 and rebuild
itself unattended. Three reasons that is currently wrong here:

- It tracks the **pushed** repo, not your working copy. Any deploy-rs deploy of unpushed local
  changes would survive only until 04:00.
- The committed `hosts/playground/configuration.nix` still holds placeholder settings
  (`domain = "yourdomain.com"`, `hostId = "1a23bc45"`). Activating that generation would give the
  host the wrong `networking.hostId`, and the next boot would fail to `zpool import tank`.
- There is no equivalent of deploy-rs' magic rollback. A broken commit you pushed applies
  unattended with nothing to catch it. `allowReboot` is `false`, so kernel and initrd updates
  would be built but never actually booted until you reboot by hand.

Re-enable only after pushing a commit that reproduces the running host exactly.

To make the host track only what you deploy, set `system.autoUpgrade.enable = false;` in
`modules/common/nix.nix`.

Unrelated but adjacent: the same file runs weekly GC (`--delete-older-than 14d`), which also
prunes the old generations you would roll back to. Don't count on a three-week-old generation
still being there.

## Misc

- **Add a new host**: copy `hosts/playground/`, adjust hostname/disk/hardware config, add to
  `nixosConfigurations` *and* `deploy.nodes` in `flake.nix`, install with nixos-anywhere.
- **Disk layout**: GPT on `/dev/sda` — 1M BIOS boot, 512M ESP, ZFS pool. Edit [
  `disk-config.nix`](hosts/playground/disk-config.nix) to change.
- **Secrets**: see [modules/secrets/README.md](modules/secrets/README.md).
- **Validate**: `nix eval .#deploy.nodes.playground.profiles.system.path` — forces every
  container's config, which `nix flake check` alone does not. Logs on host: `journalctl -b`.

## Documentation

See the full [documentation index](DOCS.md) for module-specific guides.

| File                                                                 | Contents                                                                                    |
|:---------------------------------------------------------------------|:--------------------------------------------------------------------------------------------|
| [README.md](README.md)                                               | Repo layout, current services (IPs, ports, URLs, ZFS datasets), deploy + upgrade + rollback |
| [INSTALLATION.md](INSTALLATION.md)                                   | Fresh install: pre-install config, nixos-anywhere, post-install, verification               |
| [modules/common/network/README.md](modules/common/network/README.md) | SSH, mDNS, Traefik + Cloudflare Tunnel, Let's Encrypt certificate                           |
| [modules/common/zfs/README.md](modules/common/zfs/README.md)         | ZFS datasets, snapshots, backup/replication, management commands                            |
| [modules/containers/README.md](modules/containers/README.md)         | Container structure, service skeletons, resource limits, persistent storage                 |
| [modules/secrets/README.md](modules/secrets/README.md)               | sops-nix setup, age keys, secrets vs config variables                                       |
