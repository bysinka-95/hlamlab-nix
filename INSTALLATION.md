# Installation Guide

Getting this config onto a fresh machine. Two different tools, one each:

| Stage                       | Tool               | Why                                                                                                                       |
|-----------------------------|--------------------|---------------------------------------------------------------------------------------------------------------------------|
| First install, bare machine | **nixos-anywhere** | Partitions the disk (disko) and installs NixOS over SSH from the installer ISO. There is nothing to deploy *to* yet.      |
| Every deploy after that     | **deploy-rs**      | Builds on the target, activates with auto-rollback if the host goes unreachable. See [README § Deploy](README.md#deploy). |

Do not reach for nixos-anywhere again after Part 2 — it repartitions the disk.

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

Check [`hosts/playground/disk-config.nix`](hosts/playground/disk-config.nix) — default device is
`/dev/sda`. If your
target machine uses a different disk (e.g., NVMe drives often show as `/dev/nvme0n1`), update the
device path
accordingly.

### 4. Set ZFS host ID (before first install)

Read the host ID from the target machine during installation, then set it in [
`hosts/playground/configuration.nix`](hosts/playground/configuration.nix) **before** running
`nixos-anywhere`.

```bash
# On the target machine (installer shell)
head -c 8 /etc/machine-id; echo
```

```nix
  hlamlab.settings.hostId = "<8-hex-chars>";
```

> Important: do not change this value after initial installation. If the pool was created/imported
> with a different host ID, changing `hostId` later can prevent `tank` from importing at boot.

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
  dns-api-token: "placeholder" # Let's Encrypt DNS-01, see network README

traefik:
  dashboard-auth: "placeholder (htpasswd format: username:bcrypt_hash)"

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

grafana:
  oidc-client-secret: "placeholder" # same value used by the Authelia grafana client
  admin-password: "placeholder"     # break-glass local admin (login form disabled)
  secret-key: "placeholder"         # Grafana DB encryption key — keep stable
```

**Generate Application Secrets:**

To generate secure values, we use the `authelia` CLI tool via Nix to ensure they meet length and
complexity requirements perfectly, and `openssl` for the RSA keys:

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

# Generate Grafana secrets
nix run nixpkgs#authelia -- crypto rand --length 72 --charset rfc3986 # Use for grafana-oidc-client-secret (same value in the Authelia grafana client)
nix run nixpkgs#authelia -- crypto rand --length 32 --charset alphanumeric # Use for grafana-secret-key (DB encryption key)
# grafana-admin-password: choose a strong password (break-glass only; the login form is disabled)

# Generate Traefik Dashboard Auth Secret (htpasswd format)
# Set username and password for basicAuth (default is username 'traefik-cloudflared' with a bcrypt hash)
nix run nixpkgs#apacheHttpd -- htpasswd -B -n traefik-cloudflared # Enter a strong password when prompted; copy the printed line

# Generate an RSA Keypair for the Authelia OIDC Issuer
openssl genrsa -out private.pem 4096
# Copy the contents of private.pem into authelia-oidc-issuer-private-key, keeping the indentation
cat private.pem
rm private.pem
```

Replace the placeholders in your `secrets.yaml` file with the generated values.

The Cloudflare DNS token and tunnel credentials can be real already — see
[network README](modules/common/network/README.md#certificate-and-credentials). Traefik obtains
its Let's Encrypt certificate by itself on first start.

### 7. Validate

```bash
nix flake check
```

---

## Part 2: Installation

Boot the target machine with the [NixOS installer ISO](https://nixos.org/download.html#nixos-iso),
then:

```bash
# On target machine:
ip a          # note IP
passwd        # set temporary root password for nixos-anywhere SSH
head -c 8 /etc/machine-id; echo # save this for hlamlab.settings.hostId (Part 1, step 4)
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

From here on every deploy is deploy-rs. The target host, SSH user, remote build and rollback
behaviour all live in [`flake.nix`](flake.nix) under `deploy`, so the command carries no flags:

```bash
git add -A  # Nix ignores untracked files — stage first
nix run nixpkgs#deploy-rs -- .#playground
```

`flake.nix` targets `playground.local` over mDNS. Avahi needs ~30s after boot, and some networks
block mDNS entirely — override for this deploy without editing the flake:

```bash
nix run nixpkgs#deploy-rs -- .#playground --hostname <target-ip>
```

If activation succeeds but the host stops answering SSH, deploy-rs does **not** confirm and the
host rolls itself back — you get your previous generation, not a brick. See
[README § Deploy](README.md#deploy) for `--dry-activate` / `--test` and manual rollback.

### 4. Update real secrets

Replace any remaining placeholders — the Cloudflare DNS token and tunnel credentials in
particular. See [network README](modules/common/network/README.md#certificate-and-credentials).

After secrets are updated and deployed, reboot once or restart the affected services.

```bash
# Option A: simplest and safest
ssh hlamnix@<target-ip> "sudo reboot"

# Option B: restart only related services
ssh hlamnix@<target-ip> "sudo systemctl restart cloudflared traefik"
```

### 5. Create your everyday user in LLDAP

LLDAP's built-in `admin` (password: `lldap-user-pass`) manages the directory. Keep it for
that — don't log in to the services with it. Create yourself a separate everyday user
in the LLDAP UI (`https://lldap.<domain>`, log in as `admin`):

1. Create the user. Fill in **Display name** and **Email** — OpenCloud refuses users
   without a display name.
2. Add it to the group `admins` (created on deploy by `lldap-bootstrap` in
   `modules/containers/lldap.nix`). Members of `admins` become Grafana server admins,
   Immich admins and OpenCloud admins; everyone else gets regular accounts.
3. Don't add it to `lldap_admin`: that group can edit the directory itself.

Log in to Grafana at `https://grafana.<domain>` — you are redirected straight to
Authelia (the local login form is disabled).

> Break-glass: if OIDC ever breaks, set `auth.disable_login_form = false` in
> `grafana.nix` for one rebuild and log in with `admin` / `grafana-admin-password`.

---

## Verification

```bash
ping playground.local                          # mDNS working
ssh hlamnix@playground.local "zpool status"    # ZFS healthy
ssh hlamnix@playground.local "zfs list"        # datasets exist
ssh hlamnix@playground.local "machinectl list" # containers running
systemctl status traefik                       # (on host)

# Observability
ssh hlamnix@playground.local "ls /var/log/journal/"        # host + per-container machine-id dirs
ssh hlamnix@playground.local "journalctl -M immich -n 5"   # container logs visible from host
ssh hlamnix@playground.local "systemctl status alloy"      # log agent healthy
# Prometheus targets all UP (from the host, via the gateway IP):
ssh hlamnix@playground.local "curl -s 10.0.0.10:9090/api/v1/targets | grep -o '\"health\":\"[^\"]*\"' | sort | uniq -c"
```

---

## Troubleshooting

**SSH fails post-install** — verify target is booted (`ping <ip>`); check `systemctl status sshd`
via console.

**`playground.local` not resolving** — wait 30s after boot for Avahi; use IP directly in the
meantime.

**Secrets decryption fails** — verify age key is at the right path (macOS:
`~/Library/Application Support/sops/age/keys.txt`; Linux: `~/.config/sops/age/keys.txt`).
Check key is in `.sops.yaml` (`grep age1 .sops.yaml`), then re-run `sops updatekeys`.

**ZFS pool not importing** — `sudo zpool import -f tank`. Verify `networking.hostId` was set before
first install and has not changed since installation.

**Disk errors** — `sudo wipefs -a /dev/sda` (⚠ destroys all data), then re-run nixos-anywhere.

**deploy-rs: your change isn't in the build** — Nix cannot see untracked files. `git add -A` and
redeploy. `Git tree ... is dirty` is only a warning; *untracked* is the silent failure.

**deploy-rs: `Failed to confirm the deployment`** — activation worked but the confirmation SSH
never landed, so the host rolled back. Either the change broke connectivity (that is the feature
working), or the box was still busy starting containers. Bump `confirmTimeout` in `flake.nix`, or
re-run with `--confirm-timeout 300`.

**deploy-rs: sudo prompts or permission denied** — activation runs as `root` via passwordless
sudo (`security.sudo.extraRules` in `hosts/playground/configuration.nix`). If you removed that
rule, set `interactiveSudo = true;` on the node in `flake.nix` instead.

**`systemd-machined.socket: ... already active, refusing`** — nspawn containers D-Bus-activate
machined before switch-to-configuration starts its socket unit; the failed unit then fails the
whole switch and deploy-rs rolls back. Handled by
`systemd.suppressedSystemUnits = [ "systemd-machined.socket" ]` in the host config. Do not "fix"
it by masking `systemd-machined.service` — masking it while it runs makes systemd drop its
watchdog pings and SIGABRT it three minutes later, and takes `machinectl` with it.

---

## Next steps

Day-to-day deploys, upgrading nixpkgs, and rollback: [README § Deploy](README.md#deploy) and
[README § Upgrading](README.md#upgrading).
