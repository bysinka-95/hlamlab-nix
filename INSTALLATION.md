# Installation Guide

Deploying this config to a fresh machine with nixos-anywhere.

---

## Part 1: Pre-Installation

### 1. Add your SSH key

Edit [`hosts/playground/configuration.nix`](hosts/playground/configuration.nix):

```nix
users.users.hlamnix.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3..." ];
```

### 2. Set a user password

```bash
nix run nixpkgs#mkpasswd -- -m sha-512
```

Paste the output hash into `users.users.hlamnix.hashedPassword` in [
`configuration.nix`](hosts/playground/configuration.nix).

### 3. Verify disk device

Check [`hosts/playground/disk-config.nix`](hosts/playground/disk-config.nix) — default device is `/dev/sda`. If your
target machine uses a different disk (e.g., NVMe drives often show as `/dev/nvme0n1`), update the device path
accordingly.

### 4. Set ZFS host ID (before first install)

Read the host ID from the target machine during installation, then set it in [`modules/common/settings.nix`](modules/common/settings.nix) **before** running `nixos-anywhere`.

```bash
# On the target machine (installer shell)
head -c 8 /etc/machine-id; echo
```

```nix
hostId = "<8-hex-chars>";
```

> Important: do not change this value after initial installation. If the pool was created/imported with a different host ID, changing `hostId` later can prevent `tank` from importing at boot.

### 5. Set up secrets

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
cloudflare:
  credentials: |
    {
      "AccountTag": "...",
      "TunnelID": "...",
      "TunnelSecret": "..."
    }
  origin-ca: |
    -----BEGIN CERTIFICATE-----
    placeholder
    -----END CERTIFICATE-----

traefik:
  origin-cert: |
    -----BEGIN CERTIFICATE-----
    placeholder
    -----END CERTIFICATE-----
  origin-key: |
    -----BEGIN PRIVATE KEY-----
    placeholder
    -----END PRIVATE KEY-----

authelia:
  jwt-secret: "placeholder"
  session-secret: "placeholder"
  storage-encryption-key: "placeholder"
  oidc-hmac-secret: "placeholder"
  oidc-issuer-private-key: |
    -----BEGIN PRIVATE KEY-----
    placeholder
    -----END PRIVATE KEY-----

immich:
  oidc-client-secret: "placeholder"

lldap:
  jwt-secret: "placeholder"
  user-pass: "placeholder"

vaultwarden:
  oidc-client-secret: "placeholder"
  env: |
    ADMIN_TOKEN=placeholder
    SSO_CLIENT_SECRET=placeholder # same as vaultwarden.oidc-client-secret

searx:
  env: |
    SEARX_SECRET_KEY=placeholder

opencloud:
  sharing-secret: |
    SHARING_SERVICE_ACCOUNT_SECRET=placeholder
```

**Generate Application Secrets:**

To generate secure values, we use the `authelia` CLI tool via Nix to ensure they meet length and complexity requirements perfectly, and `openssl` for the RSA keys:

```bash
# Generate 64-character alphanumeric secrets for Authelia
nix run nixpkgs#authelia -- crypto rand --length 64 --charset alphanumeric # Use for authelia-jwt-secret
nix run nixpkgs#authelia -- crypto rand --length 64 --charset alphanumeric # Use for authelia-session-secret
nix run nixpkgs#authelia -- crypto rand --length 64 --charset alphanumeric # Use for authelia-storage-encryption-key
nix run nixpkgs#authelia -- crypto rand --length 64 --charset alphanumeric # Use for authelia-oidc-hmac-secret

# Generate a 72-character random string for the Immich OIDC client secret
nix run nixpkgs#authelia -- crypto rand --length 72 --charset rfc3986 # Use for immich-oidc-client-secret

# Generate LLDAP Secrets
nix run nixpkgs#authelia -- crypto rand --length 64 --charset alphanumeric # Use for lldap-jwt-secret
# Choose a strong password for lldap-user-pass

# Generate Vaultwarden secrets
# SSO client secret (shared between Vaultwarden and Authelia — same value in both keys)
nix run nixpkgs#authelia -- crypto rand --length 64 --charset alphanumeric # Use for vaultwarden-oidc-client-secret AND SSO_CLIENT_SECRET in vaultwarden-env

# ADMIN_TOKEN: generate an Argon2 hash (Vaultwarden accepts this natively)
nix run nixpkgs#authelia -- crypto hash generate argon2 # Enter a strong passphrase when prompted; use the printed hash as ADMIN_TOKEN

# Then put both values into the vaultwarden-env multiline secret:
# vaultwarden-env: |
#   ADMIN_TOKEN=<argon2 hash from above>
#   SSO_CLIENT_SECRET=<same value as vaultwarden-oidc-client-secret>

# Generate SearXNG secrets
nix run nixpkgs#authelia -- crypto rand --length 64 --charset alphanumeric # Use for SEARX_SECRET_KEY in searx-env

# Generate an RSA Keypair for the Authelia OIDC Issuer
openssl genrsa -out private.pem 4096
# Copy the contents of private.pem into authelia-oidc-issuer-private-key, keeping the indentation
cat private.pem
rm private.pem
```

Replace the placeholders in your `secrets.yaml` file with the generated values.

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
