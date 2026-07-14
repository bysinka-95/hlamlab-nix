# Hlamlab NixOS homelab

Flake-based NixOS configuration for the homelab. `playground` is the current Proxmox VM target used
to iterate toward
the eventual host migration.

## Repo layout

- [`flake.nix`](flake.nix): Flake inputs and `flake-parts` based `nixosConfigurations`.
- [`modules/common/`](modules/common): Shared defaults (nix settings, allowUnfree, SSH policy, base packages) and the `container-frame.nix` abstraction.
- [`modules/common/network/`](modules/common/network): Network services (Traefik reverse proxy, Cloudflare Tunnel, mDNS).
- [`modules/common/zfs/`](modules/common/zfs): ZFS configuration (declarative datasets, snapshots, monitoring).
- [`modules/secrets/`](modules/secrets): sops-nix configuration and encrypted secrets. All configuration variables live inside `secrets.yaml` encrypted using sops-nix.
- [`modules/containers/`](modules/containers): Self-contained service definitions using the `hlamlab.services` abstraction.
- [`hosts/playground/`](hosts/playground)
    - [`configuration.nix`](hosts/playground/configuration.nix): System config (boot, networking, users). This is where services are explicitly enabled.
    - [`disk-config.nix`](hosts/playground/disk-config.nix): Disko ZFS layout for `/dev/sda` (GPT + ESP + ZFS pool).
    - [`hardware-configuration.nix`](hosts/playground/hardware-configuration.nix): Generated hardware profile; replace/regenerate per machine.

## Current Services

### Network Infrastructure

| Service           | Binding    | URL                        | Notes                                    |
|-------------------|------------|----------------------------|------------------------------------------|
| Traefik           | :443       | https://traefik.yourdomain | Dashboard (basic auth); HTTP :80 → HTTPS |
| Cloudflare Tunnel | (outbound) | Covers all `*.yourdomain`  | Routes → Traefik :443 with mTLS          |

- **Traefik** — [`modules/common/network/traefik.nix`](modules/common/network/traefik.nix):
  entrypoints, mTLS
  enforcement, shared middlewares (`security-headers`, `rate-limit`), dashboard router.
  Logs: `/var/log/traefik/traefik.log` and `/var/log/traefik/access.log`.
- **Cloudflare Tunnel** — [
  `modules/common/network/cloudflared.nix`](modules/common/network/cloudflared.nix): routes all
  `*.yourdomain` → `https://localhost:443`. Credentials managed via sops-nix.
  See [Network README](modules/common/network/README.md) for mTLS certificate setup.

### Application Containers

| Service      | IP:Port            | URL                                                         | Storage Path                   | CPU  | RAM (high → max) | ZFS Quota / Res |
|--------------|--------------------|-------------------------------------------------------------|--------------------------------|------|------------------|-----------------|
| opencloud    | 10.0.0.2:9200      | https://opencloud.yourdomain                                | /var/lib/services/opencloud    | 100% | 1.5G → 2G        | 50G / 10G       |
| immich       | 10.0.0.3:2283      | https://immich.yourdomain                                   | /var/lib/services/immich       | 200% | 3G → 4G          | 300G / 10G      |
| collabora    | 10.0.0.4:9980      | https://collabora.yourdomain                                | /var/lib/services/collabora    | 100% | 1G → 1.5G        | 20G / 5G        |
| authelia     | 10.0.0.5:8443      | https://auth.yourdomain                                     | /var/lib/services/authelia     | 100% | 512M → 1G        | 10G / 1G        |
| lldap        | 10.0.0.6:3000      | https://lldap.yourdomain                                    | /var/lib/services/lldap        | 100% | 512M → 1G        | 10G / 1G        |
| vaultwarden  | 10.0.0.7:8222      | https://vault.yourdomain                                    | /var/lib/services/vaultwarden  | 100% | 512M → 1G        | 10G / 1G        |
| searx        | 10.0.0.8:8888      | https://searxng.yourdomain                                  | /var/lib/services/searx        | 100% | 512M → 1G        | 10G / 1G        |
| —            | 10.0.0.9+          | —                                                           | —                              | —    | —                | —               |

**IP 10.0.0.1** is reserved for the host gateway. **Next available:** 10.0.0.9.

### ZFS Datasets

| Dataset                      | Mount                          | Quota | Reservation | Compression |
|------------------------------|--------------------------------|-------|-------------|-------------|
| tank/root                    | /                              | —     | —           | lz4         |
| tank/nix                     | /nix                           | —     | —           | lz4         |
| tank/home                    | /home                          | —     | —           | lz4         |
| tank/services                | /var/lib/services              | —     | —           | lz4         |
| tank/services/opencloud      | /var/lib/services/opencloud    | 50G   | 10G         | lz4         |
| tank/services/immich         | /var/lib/services/immich       | 300G  | 10G         | lz4         |
| tank/services/collabora      | /var/lib/services/collabora    | 20G   | 5G          | lz4         |
| tank/services/authelia       | /var/lib/services/authelia     | 10G   | 1G          | lz4         |
| tank/services/lldap          | /var/lib/services/lldap        | 10G   | 1G          | lz4         |
| tank/services/vaultwarden    | /var/lib/services/vaultwarden  | 10G   | 1G          | lz4         |
| tank/services/searx          | /var/lib/services/searx        | 10G   | 1G          | lz4         |
| tank/backups                 | /var/backups                   | —     | —           | gzip        |

For ZFS management commands, snapshot operations, and adding new datasets, see
[ZFS Module Documentation](modules/common/zfs/README.md).
For container management commands and how to add new services, see
[Container Module Documentation](modules/containers/README.md).

## Prerequisites

- Nix with flakes enabled on the build machine.
- SSH reachability to the target (root or nixos user) and your SSH public key present on the target.
- For fresh installs: access to the target disk (`/dev/sda` assumed) and ability to reboot.
- Tools (install via Nix if needed):
    - `nixos-anywhere` for remote installations.
    - `nixos-rebuild` via `nix run nixpkgs#nixos-rebuild` for deploys.
- Default admin user: `hlamnix` (wheel/networkmanager). Set its hashed password in [
  `hosts/playground/configuration.nix`](hosts/playground/configuration.nix)
  by replacing `<replace-with-mkpasswd-sha-512>` with the output of `mkpasswd -m sha-512`.

## Initial Configuration

Before deploying, edit the configuration file with your values:

**Edit [`modules/common/settings.nix`](modules/common/settings.nix)**:

```nix
let
  domain = "yourdomain.com";           # Your domain name
  tunnelId = "your-tunnel-id-here";    # Your Cloudflare Tunnel ID
  hostId = "your-zfs-host-id";         # Your ZFS host ID (8 hex chars)
  ...
in
{
  inherit domain tunnelId hostId ldapBaseDn;
}
```

**Note**: This file is tracked by git. If publishing this config publicly, use dummy placeholder
values (e.g., "
example.com", "00000000-0000-0000-0000-000000000000") and document that users should update them.

## Installation

See **[INSTALLATION.md](INSTALLATION.md)** for the complete guide (pre-install config,
nixos-anywhere, post-install
steps, and troubleshooting).

## Rebuild / Deploy Changes

Run from the repo root after editing configs:

```sh
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#playground \
  --target-host hlamnix@<playground-ip> \
  --build-host hlamnix@<playground-ip> \
  --sudo \
  --ask-sudo-password
```

**Options:**

- Build locally and push: replace `--build-host hlamnix@<playground-ip>` with
  `--build-host localhost`
- Dry-run test: add `--dry-run` to see what would change

## Misc

- **Update flake inputs**: `nix flake update` then rebuild.
- **Add a new host**: copy `hosts/playground/`, adjust hostname/disk/hardware config, add to
  `flake.nix`, install with
  nixos-anywhere.
- **Disk layout**: GPT on `/dev/sda` — 1M BIOS boot, 512M ESP, ZFS pool. Edit [
  `disk-config.nix`](hosts/playground/disk-config.nix) to change.
- **Secrets**: see [modules/secrets/README.md](modules/secrets/README.md).
- **Validate**: `nix flake check`. Logs on host: `journalctl -b`.

## Documentation

See the full [documentation index](DOCS.md) for module-specific guides.

| File | Contents |
| :--- | :--- |
| [README.md](README.md) | Repo layout, current services (IPs, ports, URLs, ZFS datasets), deploy command |
| [INSTALLATION.md](INSTALLATION.md) | Fresh install: pre-install config, nixos-anywhere, post-install, verification |
| [modules/common/network/README.md](modules/common/network/README.md) | SSH, mDNS, Traefik + Cloudflare Tunnel, mTLS certificates |
| [modules/common/zfs/README.md](modules/common/zfs/README.md) | ZFS datasets, snapshots, backup/replication, management commands |
| [modules/containers/README.md](modules/containers/README.md) | Container structure, service skeletons, resource limits, persistent storage |
| [modules/secrets/README.md](modules/secrets/README.md) | sops-nix setup, age keys, secrets vs config variables |
