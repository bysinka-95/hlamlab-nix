# Installation Guide

Deploying this config to a fresh machine with nixos-anywhere.

---

## Part 1: Pre-Installation

### 1. Configure local variables

Edit [`modules/common/local.nix`](modules/common/local.nix):

```nix
{ domain = "yourdomain.com"; tunnelId = "your-tunnel-id-here"; }
```

### 2. Add your SSH key

Edit [`hosts/playground/configuration.nix`](hosts/playground/configuration.nix):

```nix
users.users.hlamnix.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3..." ];
```

### 3. Set a user password

```bash
nix run nixpkgs#mkpasswd -- -m sha-512
```

Paste the output hash into `users.users.hlamnix.hashedPassword` in [
`configuration.nix`](hosts/playground/configuration.nix).

### 4. Verify disk device

Check [`hosts/playground/disk-config.nix`](hosts/playground/disk-config.nix) — default device is `/dev/sda`. If your
target machine uses a different disk (e.g., NVMe drives often show as `/dev/nvme0n1`), update the device path
accordingly.

### 5. Set ZFS host ID (before first install)

Read the host ID from the target machine during installation, then set it in [`modules/common/zfs/default.nix`](modules/common/zfs/default.nix) **before** running `nixos-anywhere`.

```bash
# On the target machine (installer shell)
head -c 8 /etc/machine-id; echo
```

```nix
networking.hostId = "<8-hex-chars>";
```

> Important: do not change this value after initial installation. If the pool was created/imported with a different host ID, changing `networking.hostId` later can prevent `tank` from importing at boot.

### 6. Set up secrets

**Generate your age key:**

```bash
# macOS
mkdir -p ~/Library/Application\ Support/sops/age
nix run nixpkgs#age -- -generate -o ~/Library/Application\ Support/sops/age/keys.txt
nix run nixpkgs#age -- -y ~/Library/Application\ Support/sops/age/keys.txt  # prints public key

# Linux
mkdir -p ~/.config/sops/age
nix run nixpkgs#age -- -generate -o ~/.config/sops/age/keys.txt
nix run nixpkgs#age -- -y ~/.config/sops/age/keys.txt
```

**Edit [`.sops.yaml`](.sops.yaml):**

```yaml
keys:
  - &admin age1abc123...     # your public key from above
  - &playground age1xyz...   # added post-install (step 3.2)
creation_rules:
  - path_regex: secrets/secrets.yaml$
    key_groups:
      - age: [*admin, *playground]
```

**Initialize secrets file with placeholders:**

```bash
nix run nixpkgs#sops -- modules/secrets/secrets.yaml
```

```yaml
cloudflared-credentials: "placeholder"
traefik-origin-cert: |
  -----BEGIN CERTIFICATE-----
  placeholder
  -----END CERTIFICATE-----
traefik-origin-key: |
  -----BEGIN PRIVATE KEY-----
  placeholder
  -----END PRIVATE KEY-----
cloudflare-origin-ca: |
  -----BEGIN CERTIFICATE-----
  placeholder
  -----END CERTIFICATE-----
kanidm-admin-password: "placeholder"
immich-oidc-client-secret: "placeholder"
```

Real certificates are added post-install. See [network README](modules/common/network/README.md#required-certificates).

### 7. Validate

```bash
nix flake check
```

---

## Part 2: Installation

Boot the target machine with the [NixOS installer ISO](https://nixos.org/download.html#nixos-iso), then:

```bash
# On target machine:
ip a          # note IP
passwd        # set temporary root password for nixos-anywhere SSH
head -c 8 /etc/machine-id; echo # save this for networking.hostId (Part 1, step 5)
```

From your local machine:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake '.#playground' \
  --generate-hardware-config nixos-generate-config ./hosts/playground/hardware-configuration.nix \
  --target-host nixos@<target-ip> \
  --build-on remote
```

`--build-on remote` is required when deploying from a different architecture (e.g., ARM → x86_64).

---

## Part 3: Post-Installation

### 1. Get host age key

```bash
ssh hlamnix@<target-ip>
nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
```

### 2. Add host key to sops

Add the printed `age1...` key to `.sops.yaml` as `&playground`, then:

```bash
nix run nixpkgs#sops -- updatekeys modules/secrets/secrets.yaml
```

### 3. Deploy

```bash
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#playground \
  --target-host hlamnix@<target-ip> \
  --build-host hlamnix@<target-ip> \
  --sudo --ask-sudo-password
```

### 4. Update real secrets

Replace placeholder values in secrets with actual Cloudflare certificates and tunnel credentials.
See [network README](modules/common/network/README.md#required-certificates).

After secrets are updated and deployed, reboot once or restart the affected services.

```bash
# Option A: simplest and safest
ssh hlamnix@<target-ip> "sudo reboot"

# Option B: restart only related services
ssh hlamnix@<target-ip> "sudo systemctl restart cloudflared traefik"
```

---

## Verification

```bash
ping playground.local                          # mDNS working
ssh hlamnix@playground.local "zpool status"    # ZFS healthy
ssh hlamnix@playground.local "zfs list"        # datasets exist
ssh hlamnix@playground.local "machinectl list" # containers running
systemctl status traefik                       # (on host)
```

---

## Troubleshooting

**SSH fails post-install** — verify target is booted (`ping <ip>`); check `systemctl status sshd` via console.

**`playground.local` not resolving** — wait 30s after boot for Avahi; use IP directly in the meantime.

**Secrets decryption fails** — verify age key is at the right path (macOS:
`~/Library/Application Support/sops/age/keys.txt`; Linux: `~/.config/sops/age/keys.txt`).
Check key is in `.sops.yaml` (`grep age1 .sops.yaml`), then re-run `sops updatekeys`.

**ZFS pool not importing** — `sudo zpool import -f tank`. Verify `networking.hostId` was set before first install and has not changed since installation.

**Disk errors** — `sudo wipefs -a /dev/sda` (⚠ destroys all data), then re-run nixos-anywhere.
