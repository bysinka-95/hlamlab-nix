# Secrets management

sops-nix and age encrypt the secrets in [`secrets.yaml`](secrets.yaml).
[`default.nix`](default.nix) declares the host secrets. Each service module declares its container
secrets (`secrets.<id>`).

**Only the host decrypts.** It uses its SSH host key, which is the host recipient in `.sops.yaml`.
Containers have no key and no sops file. The frame gives each container its own secrets as
systemd credentials. nspawn copies them into RAM at container start. See
[hosts/README.md § Secrets](../../hosts/README.md#secrets).

---

## Setup

[INSTALLATION.md](../../INSTALLATION.md) has the full steps:

1. Make your personal age key (Part 1, step 6).
2. Write `.sops.yaml` with your key and the host key.
3. Create `secrets.yaml` and fill in the values.
4. After the install, add the host key (Part 3, steps 1 and 2).

`.sops.yaml` for one host:

```yaml
keys:
  - &admin age1...      # your personal age key
  - &playground age1... # host key (ssh-to-age of /etc/ssh/ssh_host_ed25519_key.pub)
creation_rules:
  - path_regex: modules/secrets/secrets\.yaml$
    key_groups:
      - age: [*admin, *playground]
```

---

## Usage

| Task              | Command or action                                                                     |
|-------------------|---------------------------------------------------------------------------------------|
| Edit secrets      | `nix run nixpkgs#sops -- modules/secrets/secrets.yaml`                                |
| Add a host secret | Declare it in `default.nix`, then add its value with sops                             |
| Add a container secret | Declare it in `secrets.<id>` of the service module, then add its value with sops |
| Change recipients | Edit `.sops.yaml`, then `nix run nixpkgs#sops -- updatekeys modules/secrets/secrets.yaml` |

sops-nix checks at build time that each declared key exists in `secrets.yaml`. A missing key stops
the build.

---

## Secrets and plain settings

`secrets.yaml` keeps all secrets in nested YAML groups: the Cloudflare credentials and DNS API
token, the service environments, the OIDC client secrets and the passwords.

```yaml
cloudflare:
  credentials: "..."
  dns-api-token: "..."       # Let's Encrypt DNS-01 (Zone:DNS:Edit + Zone:Zone:Read, one zone)
crowdsec:
  bouncer-key: "..."         # Traefik bouncer's LAPI key; rotating it re-registers the bouncer
searx:
  env: "..."
grafana:
  oidc-client-secret: "..."  # SAME value referenced by the Authelia grafana client
  admin-password: "..."      # break-glass only (login form disabled)
  secret-key: "..."          # Grafana DB encryption key — keep stable, never rotate casually
# ...
```

The plain build-time settings (`domain`, `tunnelId`, `hostId`, `lanInterface`) are in the host
configuration. [`modules/common/settings.nix`](../common/settings.nix) declares them.

---

## What to commit

✅ **Safe**: `modules/secrets/secrets.yaml` (encrypted) and `.sops.yaml` (public keys only).

❌ **Never**: `keys.txt` (your age private key) or any decrypted secret file.
