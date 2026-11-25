# Installation guide

This guide puts the configuration on a new machine. It uses two tools:

| Stage                       | Tool               | Why                                                                                                                 |
|-----------------------------|--------------------|---------------------------------------------------------------------------------------------------------------------|
| First install, bare machine | **nixos-anywhere** | It partitions the disk (disko) and installs NixOS over SSH from the installer ISO. There is no system to deploy to. |
| Each deploy after that      | **deploy-rs**      | It builds on the target and rolls back if the host becomes unreachable. See [README § Deploy](README.md#deploy).    |

Do not run nixos-anywhere again after Part 2. It partitions the disk again and deletes all data.

---

## Part 1: Before the install

### 1. Add your SSH key

Edit [`hosts/playground/configuration.nix`](hosts/playground/configuration.nix):

```nix
users.users.hlamnix.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3..." ];
```

### 2. Set a user password

```bash
nix run nixpkgs#mkpasswd -- -m sha-512
```

Put the hash into `users.users.hlamnix.hashedPassword` in
[`configuration.nix`](hosts/playground/configuration.nix).

### 3. Check the disk device

The default device in [`hosts/playground/disk-config.nix`](hosts/playground/disk-config.nix) is
`/dev/sda`. If the target uses a different disk, change the path. NVMe disks often show as
`/dev/nvme0n1`.

### 4. Set the ZFS host ID

Read the host ID on the target in the installer shell. Set it in
[`hosts/playground/configuration.nix`](hosts/playground/configuration.nix) **before** you run
nixos-anywhere.

```bash
# On the target machine (installer shell)
head -c 8 /etc/machine-id; echo
```

```nix
  hlamlab.settings.hostId = "<8-hex-chars>";
```

> Do not change this value after the install. ZFS records the host ID in the pool. With a
> different `hostId`, `tank` can fail to import at boot.

### 5. Set the LAN interface

Set `hlamlab.settings.lanInterface` to the name of the target's network interface. The installer
shell shows it with `ip -br link`. The default is `ens18` (Proxmox virtio).

> A wrong `lanInterface` cuts SSH. The firewall opens SSH on that interface only.

Optional: if you enable the `blocky` service, set `hlamlab.settings.lanAddress` to the target's LAN
address. Reserve that address for the target in the DHCP settings of the router. Then devices that use Blocky reach
the services at home without Cloudflare. The
[network README](modules/common/network/README.md#lan-dns-blocky) explains it.

### 6. Set up secrets

**Make your age key:**

```bash
# macOS
mkdir -p ~/Library/Application\ Support/sops/age
nix run nixpkgs#age -- -generate -o ~/Library/Application\ Support/sops/age/keys.txt
nix run nixpkgs#age -- -y ~/Library/Application\ Support/sops/age/keys.txt  # prints the public key

# Linux
mkdir -p ~/.config/sops/age
nix run nixpkgs#age -- -generate -o ~/.config/sops/age/keys.txt
nix run nixpkgs#age -- -y ~/.config/sops/age/keys.txt
```

**Edit [`.sops.yaml`](.sops.yaml):**

```yaml
keys:
  - &admin age1abc123...     # your public key from above
  - &playground age1xyz...   # added after the install (Part 3, step 2)
creation_rules:
  - path_regex: modules/secrets/secrets\.yaml$
    key_groups:
      - age: [*admin, *playground]
```

**Create the secrets file with placeholders:**

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

crowdsec:
  bouncer-key: "placeholder" # Traefik bouncer's key for the CrowdSec LAPI

authelia:
  jwt-secret: "placeholder"
  session-secret: "placeholder"
  storage-encryption-key: "placeholder"
  oidc-hmac-secret: "placeholder"
  oidc-issuer-private-key: |
    -----BEGIN PRIVATE KEY-----
    placeholder
    -----END PRIVATE KEY-----
  ldap-password: "placeholder"           # Authelia's LLDAP bind user, created automatically
  immich-oidc-digest: "placeholder"      # pbkdf2 digests of the clients' secrets, see below
  vaultwarden-oidc-digest: "placeholder"
  grafana-oidc-digest: "placeholder"
  gotify-oidc-digest: "placeholder"

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
  oidc-client-secret: "placeholder" # Authelia stores only its digest (authelia.grafana-oidc-digest)
  admin-password: "placeholder"     # break-glass local admin (login form disabled)
  secret-key: "placeholder"         # Grafana DB encryption key, keep it stable

gotify:
  oidc-client-secret: "placeholder" # Authelia stores only its digest (authelia.gotify-oidc-digest)
  admin-password: "placeholder"     # local admin, break-glass (web sign-in is through Authelia)

gatus:
  env: |
    GOTIFY_TOKEN=placeholder # token of the Gatus app in Gotify, set it after the install
```

**Generate the values:**

The `authelia` CLI makes random values with the correct length and characters. `openssl` makes
the RSA key.

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
# SSO client secret: Vaultwarden needs the plaintext twice (both keys); Authelia gets its digest
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
nix run nixpkgs#authelia -- crypto rand --length 72 --charset rfc3986 # Use for grafana-oidc-client-secret
nix run nixpkgs#authelia -- crypto rand --length 32 --charset alphanumeric # Use for grafana-secret-key (DB encryption key)
# grafana-admin-password: choose a strong password (break-glass only; the login form is disabled)

# Generate Gotify secrets
nix run nixpkgs#authelia -- crypto rand --length 72 --charset rfc3986 # Use for gotify-oidc-client-secret
nix run nixpkgs#authelia -- crypto rand --length 32 --charset alphanumeric # Use for gotify-admin-password

# Generate an RSA Keypair for the Authelia OIDC Issuer
openssl genrsa -out private.pem 4096
# Copy the contents of private.pem into authelia-oidc-issuer-private-key, keeping the indentation
cat private.pem
rm private.pem

# CrowdSec: the Traefik bouncer's LAPI key (registered automatically at each CrowdSec start)
nix run nixpkgs#authelia -- crypto rand --length 64 --charset alphanumeric # Use for crowdsec-bouncer-key

# Authelia's own LLDAP bind user (read-only; lldap-bootstrap creates it)
nix run nixpkgs#authelia -- crypto rand --length 64 --charset alphanumeric # Use for authelia-ldap-password
```

Replace the placeholders in `secrets.yaml` with the generated values.

**Authelia does not keep the OIDC client secrets.** It keeps only their pbkdf2 digests. The
plaintext stays in the container of each client. When the client secrets are in `secrets.yaml`,
make the digests:

```bash
for c in immich vaultwarden grafana gotify; do
  p=$(nix run nixpkgs#sops -- -d --extract "[\"$c\"][\"oidc-client-secret\"]" modules/secrets/secrets.yaml)
  nix run nixpkgs#authelia -- crypto hash generate pbkdf2 --variant sha512 --password "$p" \
    | sed -n 's/^Digest: //p' | nix run nixpkgs#jq -- -R . \
    | nix run nixpkgs#sops -- set --value-stdin modules/secrets/secrets.yaml "[\"authelia\"][\"$c-oidc-digest\"]"
done; unset p
```

When you change a client secret, make its digest again.

You can put the real Cloudflare DNS token and tunnel credentials in now. The
[network README](modules/common/network/README.md#certificate-and-credentials) shows how to get
them. Traefik gets its Let's Encrypt certificate itself at the first start.

### 7. Check the configuration

```bash
nix flake check
```

---

## Part 2: Install

Boot the target with the [NixOS installer ISO](https://nixos.org/download.html#nixos-iso). Then
run these commands on the target:

```bash
ip a          # note the IP
passwd        # set a temporary root password for nixos-anywhere SSH
head -c 8 /etc/machine-id; echo # the value for hlamlab.settings.hostId (Part 1, step 4)
```

Then run this on your local machine:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake '.#playground' \
  --generate-hardware-config nixos-generate-config ./hosts/playground/hardware-configuration.nix \
  --target-host nixos@<target-ip> \
  --build-on remote
```

Use `--build-on remote` when your local machine has a different architecture, for example ARM to
x86_64.

---

## Part 3: After the install

### 1. Get the host age key

The host decrypts the secrets with its SSH host key. Get the age form of that key:

```bash
ssh hlamnix@<target-ip> cat /etc/ssh/ssh_host_ed25519_key.pub | nix run nixpkgs#ssh-to-age
```

### 2. Add the host key to sops

Add the printed `age1...` key to `.sops.yaml` as `&playground`. Then run:

```bash
nix run nixpkgs#sops -- updatekeys modules/secrets/secrets.yaml
```

### 3. Deploy

From now on, use deploy-rs for each deploy. [`flake.nix`](flake.nix) declares the target host, the
SSH user, the remote build and the rollback under `deploy`. The command needs no flags:

```bash
git add -A  # Nix ignores untracked files, so stage them first
nix run nixpkgs#deploy-rs -- .#playground
```

`flake.nix` uses the mDNS name `playground.local`. Avahi needs about 30 seconds after boot. Some
networks block mDNS. In these cases, give the IP for this one deploy:

```bash
nix run nixpkgs#deploy-rs -- .#playground --hostname <target-ip>
```

If the activation works but the host stops answering SSH, deploy-rs does **not** confirm the
deploy. The host then goes back to the previous generation. The
[README § Deploy](README.md#deploy) explains `--dry-activate`, `--test` and manual rollback.

### 4. Put in the real secrets

Replace all remaining placeholders, mainly the Cloudflare DNS token and the tunnel credentials.
See the [network README](modules/common/network/README.md#certificate-and-credentials).

Deploy. Then reboot once, or restart the services that use the changed secrets:

```bash
# Option A: simplest and safest
ssh hlamnix@<target-ip> "sudo reboot"

# Option B: restart only the related services
ssh hlamnix@<target-ip> "sudo systemctl restart cloudflared traefik"
```

### 5. Create your everyday user in LLDAP

The built-in LLDAP `admin` (password: `lldap-user-pass`) manages the directory. Use it only for
that. Do not log in to the services with it. Log in to the LLDAP UI as `admin` and create a
separate user for yourself.

Only members of `admins` can open `https://lldap.<domain>`. A new install has no members yet. For
the first time, open the UI through an SSH tunnel. The same tunnel works later as a break-glass
path:

```bash
ssh -N -L 17170:<lldap container ip>:3000 hlamnix@<target-ip>   # 10.0.0.6 by default
# then open http://localhost:17170
```

1. Create the user. Fill in **Display name** and **Email**. OpenCloud refuses users without a
   display name.
2. Add the user to the group `admins`. `lldap-bootstrap` in `modules/containers/lldap.nix` creates
   this group at deploy. Members of `admins` become Grafana server admins, Immich admins and
   OpenCloud admins. All other users get regular accounts.
3. Do not add the user to `lldap_admin`. Members of that group can edit the directory.

Each login needs a second factor (TOTP):

1. Log in at `https://auth.<domain>`.
2. Register an authenticator app.
3. Authelia sends a one-time code to confirm your identity. There is no mail server, so the code
   goes into a file. Read it:

```bash
ssh hlamnix@<target-ip> "sudo nixos-container run authelia -- cat /var/lib/authelia-main/notification.txt"
```

Do the same for each user that you add later. Read their code in this file and give it to them.

After this, one Authelia session opens all services. Only members of `admins` can open `lldap.`,
`traefik.` and the Vaultwarden `/admin` page. `/admin` also asks for `ADMIN_TOKEN`.

Log in to Grafana at `https://grafana.<domain>`. Grafana sends you directly to Authelia, because
its local login form is off.

> Break-glass: if OIDC stops working, set `auth.disable_login_form = false` in `grafana.nix` for
> one deploy. Then log in with `admin` and `grafana-admin-password`.

In Gotify at `https://gotify.<domain>`, select **Authelia** to log in. Members of `admins` become
Gotify admins. The local user `admin` with `gotify-admin-password` is for break-glass. The Gotify
Android app logs in with a Gotify user and keeps a client token.

Gatus sends its alerts to Gotify. Messages go to the user that owns the app, so create the app with
your own user:

1. In Gotify, open **Apps**, then **Create Application**. Use the name `Gatus`.
2. Store its token. The command does not show the token:

```bash
read -rs t; printf 'GOTIFY_TOKEN=%s' "$t" | nix run nixpkgs#jq -- -R . | nix run nixpkgs#sops -- set --value-stdin modules/secrets/secrets.yaml '["gatus"]["env"]'; unset t
```

3. Deploy. The status page is `https://status.<domain>` (Authelia, group `admins`).

---

## Checks

```bash
ping playground.local                          # mDNS works
ssh hlamnix@playground.local "zpool status"    # ZFS is healthy
ssh hlamnix@playground.local "zfs list"        # datasets exist
ssh hlamnix@playground.local "machinectl list" # containers run
ssh hlamnix@playground.local "systemctl --failed" # no failed units on the host

# CrowdSec: the traefik bouncer exists and has a recent last pull.
# It fails open, so this is the only sign that it does not work.
ssh hlamnix@playground.local "sudo -u crowdsec cscli bouncers list"

# Observability
ssh hlamnix@playground.local "sudo journalctl -M immich -n 5"   # container logs, read from the host
ssh hlamnix@playground.local "systemctl status alloy"      # host log agent is healthy
# All Prometheus targets are up:
ssh hlamnix@playground.local "curl -s 10.0.0.10:9090/api/v1/targets | grep -o '\"health\":\"[^\"]*\"' | sort | uniq -c"
```

---

## Troubleshooting

**SSH fails after the install.** Check that the target booted (`ping <ip>`). On the console, run
`systemctl status sshd`. Check that `lanInterface` is the name of the real interface.

**`playground.local` does not resolve.** Wait 30 seconds after boot for Avahi. Use the IP until
then.

**Secrets do not decrypt.** Check that your age key is at the correct path. On macOS, that is
`~/Library/Application Support/sops/age/keys.txt`. On Linux, it is `~/.config/sops/age/keys.txt`.
Check that `.sops.yaml` contains the key (`grep age1 .sops.yaml`). Then run `sops updatekeys`
again.

**The ZFS pool does not import.** Run `sudo zpool import -f tank`. Check that you set
`networking.hostId` before the first install and did not change it since.

**Disk errors.** `sudo wipefs -a /dev/sda` **deletes all data on the disk**. After it, run
nixos-anywhere again.

**deploy-rs: your change is not in the build.** Nix does not see untracked files. Run `git add -A`
and deploy again. `Git tree ... is dirty` is only a warning. An *untracked* file is the silent
failure.

**deploy-rs: `Failed to confirm the deployment`.** The activation worked, but the confirmation SSH
did not connect, so the host rolled back. The change broke the network (the rollback then did its
job), or the host was still busy with the start of the containers. Increase `confirmTimeout` in
`flake.nix`, or deploy again with `--confirm-timeout 300`.

**deploy-rs: sudo asks for a password, or permission denied.** The activation runs as `root`
through passwordless sudo (`security.sudo.extraRules` in `hosts/playground/configuration.nix`). If
you deleted that rule, set `interactiveSudo = true;` on the node in `flake.nix`.

**`systemd-machined.socket: ... already active, refusing`.** The nspawn containers start machined
through D-Bus before `switch-to-configuration` starts its socket unit. The socket unit then fails,
the switch fails and deploy-rs rolls back. The host config prevents this with
`systemd.suppressedSystemUnits = [ "systemd-machined.socket" ]`. Do not mask
`systemd-machined.service` instead. If you mask it while it runs, systemd ignores its watchdog
pings and kills it three minutes later. `machinectl` then stops working too.

---

## Next steps

For deploys, nixpkgs upgrades and rollback, see [README § Deploy](README.md#deploy) and
[README § Upgrading](README.md#upgrading).
