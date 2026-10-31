# Secrets Management

Encrypted secrets via sops-nix + age, in [`secrets.yaml`](secrets.yaml). Host secrets are declared
in [`default.nix`](default.nix); container secrets in each service module (`secrets.<id>`).

**Only the host decrypts**, with its SSH host key (the host's recipient in `.sops.yaml`). Containers
hold no key and no sops file: the frame hands each container its own secrets as systemd
credentials, copied in by nspawn at container start into RAM. See
[hosts/README.md § Managing Secrets](../../hosts/README.md#managing-secrets).

---

## Initial Setup

1. **Get the host's age key** (after first deploy):
   ```bash
   ssh hlamnix@<ip> "sudo ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"
   ```

2. **Create [`.sops.yaml`](../../.sops.yaml)**:
   ```yaml
   keys:
     - &admin age1...      # your personal age key
     - &playground age1... # host key from step 1
   creation_rules:
     - path_regex: modules/secrets/secrets\.yaml$
       key_groups:
         - age: [*admin, *playground]
   ```

3. **Generate your personal age key** (if needed):
   ```bash
   # macOS: ~/Library/Application Support/sops/age/keys.txt
   # Linux: ~/.config/sops/age/keys.txt
   nix-shell -p ssh-to-age --run 'ssh-to-age -private-key -i ~/.ssh/id_ed25519 > <keys_path>'
   ssh-to-age < ~/.ssh/id_ed25519.pub  # prints your public key for .sops.yaml
   ```

4. **Edit secrets**:
   ```bash
   sops modules/secrets/secrets.yaml
   ```

5. **Commit**:
   ```bash
   git add modules/secrets/secrets.yaml .sops.yaml && git commit -m "Add encrypted secrets"
   ```

---

## Usage

| Task           | Command                                                                  |
|----------------|--------------------------------------------------------------------------|
| Edit secrets   | `sops modules/secrets/secrets.yaml`                                      |
| Add new secret | Declare in `default.nix`, then add value via `sops secrets.yaml`         |
| Rotate keys    | Update `.sops.yaml`, then `sops updatekeys modules/secrets/secrets.yaml` |

---

## Secrets and Configuration Variables

All secrets (including Cloudflare credentials and the DNS API token, service environments, OIDC
client secrets, and passwords) are kept encrypted inside `secrets.yaml` using nested YAML groups:

```yaml
cloudflare:
  credentials: "..."
  dns-api-token: "..."       # Let's Encrypt DNS-01 (Zone:DNS:Edit + Zone:Zone:Read, one zone)
searx:
  env: "..."
grafana:
  oidc-client-secret: "..."  # SAME value referenced by the Authelia grafana client
  admin-password: "..."      # break-glass only (login form disabled)
  secret-key: "..."          # Grafana DB encryption key — keep stable, never rotate casually
# ...
```

Compile-time parameters (such as `domain`, `tunnelId`, and `hostId`) are configured in plaintext
inside [`modules/common/settings.nix`](../common/settings.nix).

---

## What to Commit

✅ **Safe**: `modules/secrets/secrets.yaml` (encrypted), `.sops.yaml` (public keys only)

❌ **Never**: `keys.txt` (your age private key), any unencrypted secret files
