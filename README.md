# Hlamlab NixOS homelab

Flake-based NixOS configuration for the homelab. `playground` is the current Proxmox VM target used to iterate toward
the eventual host migration.

> 📚 **Documentation Guide**: See [DOCS.md](DOCS.md) for an overview of all available documentation.

## Repo layout

- `flake.nix`: Inputs (nixpkgs, disko, home-manager, sops-nix, disko-zfs) and `nixosConfigurations` outputs.
- `modules/common/`: Shared defaults (nix settings, allowUnfree, SSH policy, base packages, secrets).
- `modules/common/local.nix`: **Configuration variables** (domain, tunnel ID) - **edit for your setup**.
- `modules/common/secrets/`: sops-nix configuration for encrypted secrets management.
- `modules/common/network/`: Network services (Traefik reverse proxy, Cloudflare Tunnel).
- `modules/common/zfs/`: ZFS configuration (declarative datasets, snapshots, monitoring).
- `modules/containers/`: Self-contained service modules (each with container + traefik + DNS).
- `hosts/playground/`
    - `configuration.nix`: System config (boot, networking, SSH, root keys, base packages, home-manager for root).
    - `disk-config.nix`: Disko layout for `/dev/sda` (GPT + ESP + ext4 root).
    - `hardware-configuration.nix`: Generated hardware profile; replace/regenerate per machine.

## Prerequisites

- Nix with flakes enabled on the build machine.
- SSH reachability to the target (root or nixos user) and your SSH public key present on the target.
- For fresh installs: access to the target disk (`/dev/sda` assumed) and ability to reboot.
- Tools (install via Nix if needed):
    - `nixos-anywhere` for remote installs.
    - `nixos-rebuild` via `nix run nixpkgs#nixos-rebuild` for deploys.
- Default admin user: `hlamnix` (wheel/networkmanager). Set its hashed password in `hosts/playground/configuration.nix`
  by replacing `<replace-with-mkpasswd-sha-512>` with the output of `mkpasswd -m sha-512`.

## Initial Configuration

Before deploying, edit the configuration file with your values:

**Edit `modules/common/local.nix`**:

```nix
{
  domain = "yourdomain.com";           # Your domain name
  tunnelId = "your-tunnel-id-here";    # Your Cloudflare Tunnel ID
}
```

**Note**: This file is tracked by git. If publishing this config publicly, use dummy placeholder values (e.g., "
example.com", "00000000-0000-0000-0000-000000000000") and document that users should update them.

## Services: Traefik Reverse Proxy

- Defined in `modules/common/traefik.nix`
- **Entrypoints**:
    - HTTP (`:80`) → Auto-redirects to HTTPS
    - HTTPS (`:443`) → Requires Cloudflare mTLS (origin CA verification)
- **Dashboard**: https://traefik.yourdomain (basic auth protected)
- **Configuration**: Native Nix via `dynamicConfigOptions` (no YAML files needed)
- **Logs**: `/var/log/traefik/traefik.log` and `/var/log/traefik/access.log`
- Configured routers:
    - `traefik.yourdomain` → Traefik Dashboard

## Services: Cloudflare Tunnel

- Defined in `modules/common/network/cloudflared.nix`
- **Tunnel ID**: Configured in `modules/common/local.nix`
- **Ingress**: Routes all `*.yourdomain` traffic → `https://localhost:443` (Traefik)
- **mTLS**: Validates Traefik's certificate using Cloudflare Origin CA at `/var/lib/cloudflared/origin-ca.pem`
- Credentials managed via sops-nix (encrypted in `secrets/secrets.yaml`)

For detailed setup instructions, see [modules/common/network/README.md](modules/common/network/README.md).

## Services: Containerized Applications

Each service runs in an isolated NixOS container with its own network namespace (10.0.0.x). Services are accessed via
Traefik reverse proxy.

**Current Services:**

### OpenCloud

- **URL**: https://opencloud.yourdomain
- **Container IP**: 10.0.0.2:9200
- **Features**: Identity and access management platform
- **Storage**: `/var/lib/services/opencloud` (host bind mount for persistence)
- **Important**: OpenCloud requires a valid TLS reverse proxy. Initial admin password is located in the container at
  `/etc/opencloud/opencloud.yaml` under `idm.service_user_passwords.admin_password`.

```bash
# Get initial admin password:
sudo nixos-container root-login opencloud
cat /etc/opencloud/opencloud.yaml | grep -A 2 admin_password
```

### Immich

- **URL**: https://immich.yourdomain
- **Container IP**: 10.0.0.3:2283
- **Features**: Self-hosted photo and video management
- **Storage**: `/var/lib/services/immich` (host bind mount for persistence)
- **Components**: PostgreSQL (with vector extensions), Redis, ML face detection
- **Backup Strategy**: Photos/videos stored in host filesystem for easy snapshots

**Container Management:**

```bash
# List all containers
machinectl list

# Login to a container
sudo nixos-container root-login <name>

# Check container status
systemctl status container@<name>

# View service logs
sudo nixos-container run <name> -- journalctl -u <service> -f
```

**Storage Isolation & Resource Limits:**

For advanced storage isolation with disk quotas, compression, snapshots, and CPU/RAM limits, see:

- **[ZFS Module Documentation](modules/common/zfs/README.md)** - Complete ZFS guide
- **[Resource Management](modules/containers/README.md#container-resource-limits)** - Resource management guide

For detailed container documentation and how to add new services,
see [modules/containers/README.md](modules/containers/README.md).

## Bootstrap a fresh host (example: playground VM)

1. (Optional) Update the disk layout in `hosts/playground/disk-config.nix` to match the target device.
2. Set the `hlamnix` password hash in `hosts/playground/configuration.nix`:
   ```sh
   mkpasswd -m sha-512
   ```
   Paste the result into `hashedPassword` for `hlamnix`.
3. Install remotely with nixos-anywhere (runs disko + config):
   ```sh
   nix run github:nix-community/nixos-anywhere -- \
     --flake '.#playground' \
     --generate-hardware-config nixos-generate-config ./hosts/playground/hardware-configuration.nix \
     --target-host nixos@<playground-ip>
   ```
    - Replace `<playground-ip>` with the VM IP.
    - After install, the host will reboot into the flake-defined system.

## Rebuild / deploy changes

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

- Build locally and push: replace `--build-host hlamnix@<playground-ip>` with `--build-host localhost`
- Dry-run test: add `--dry-run` to see what would change

## Add a new host

1. Copy `hosts/playground` to `hosts/<new-host>` and adjust:
    - Hostname and networking in `configuration.nix`.
    - Disk device/partitions in `disk-config.nix`.
    - Generate a new `hardware-configuration.nix` on the target (`nixos-generate-config`).
2. Add the host to `flake.nix` under `nixosConfigurations` with the correct `system`.
3. Install with nixos-anywhere (or manual ISO) and rebuild via `nixos-rebuild` using `.#<new-host>`.

## Disk layout (disko)

- Current layout: GPT on `/dev/sda`, 1M BIOS boot (EF02), 512M ESP at `/boot` (vfat), remaining ext4 root at `/`.
- To change disks or sizes, edit `hosts/<host>/disk-config.nix`; nixos-anywhere will partition/format accordingly.

## SSH keys and access

- Root SSH login is disabled; SSH as `hlamnix` (password auth enabled) or add your key to its `authorizedKeys` (shared
  with root in the config).
- Root SSH keys live in `hosts/<host>/configuration.nix` under `users.users.root.openssh.authorizedKeys.keys` and are
  reused for `hlamnix`.

## Secrets management (sops-nix)

This repo uses `sops-nix` with age encryption for secure secrets (cloudflared credentials, API tokens, etc.).

**First-time setup after deploying a host:**

1. Get the host's age public key (sops-nix auto-generates it from the SSH host key):
   ```sh
   ssh hlamnix@<playground-ip> "sudo cat /var/lib/sops-nix/key.txt | grep 'public key:' | cut -d: -f2 | tr -d ' '"
   ```

2. Create `.sops.yaml` in the repo root (replace keys with your actual values):
   ```yaml
   keys:
     - &admin age1your_personal_age_key_here
     - &playground age1host_key_from_step1_here
   creation_rules:
     - path_regex: secrets/secrets\.yaml$
       key_groups:
         - age:
             - *admin
             - *playground
   ```

3. Install sops locally and generate your personal age key:
   ```sh
   nix-shell -p sops ssh-to-age
   
   # Linux/NixOS:
   mkdir -p ~/.config/sops/age
   ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
   
   # macOS (nix-darwin):
   mkdir -p "$HOME/Library/Application Support/sops/age"
   ssh-to-age -private-key -i ~/.ssh/id_ed25519 > "$HOME/Library/Application Support/sops/age/keys.txt"
   
   # Get your public key for .sops.yaml:
   ssh-to-age < ~/.ssh/id_ed25519.pub
   ```

4. Edit `secrets/secrets.yaml` with sops and add your cloudflared credentials:
   ```sh
   sops secrets/secrets.yaml
   ```
   Replace the placeholder with:
   ```yaml
   cloudflared-credentials: |
     {"AccountTag":"xxx","TunnelSecret":"xxx","TunnelID":"xxx"}
   ```

5. Commit and deploy:
   ```sh
   git add secrets/secrets.yaml .sops.yaml
   git commit -m "Add encrypted secrets"
   # Then run nixos-rebuild to deploy
   ```

For detailed instructions, see [modules/secrets/README.md](modules/secrets/README.md).

## Updating inputs

- Update flakes (nixpkgs, home-manager, disko):
  ```sh
  nix flake update
  ```
- Review `flake.lock` changes and rebuild the target to apply.

## Troubleshooting / validation

- Check SSH: `ssh root@<playground-ip> hostname`.
- Validate flake: `nix flake check` (add tests as they are added).
- Inspect logs on host: `journalctl -u nixos-rebuild -u sshd` or `journalctl -b`.
- If hardware changes, regenerate `hardware-configuration.nix` on the host and copy it back.

## Notes for future hardening

- Root SSH login is already disabled; consider moving to key-only access for `hlamnix` once the password is confirmed
  working.
- Secrets are now managed with sops-nix; never commit unencrypted secrets to git.
- Add automated checks (CI) to run `nix flake check` on changes.
