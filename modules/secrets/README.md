# Secrets Management

Encrypted secrets via sops-nix + age. All secrets declared in [`default.nix`](default.nix), encrypted in
[`secrets.yaml`](secrets.yaml).

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

All secrets (including Cloudflare credentials, CA pull certificates, service environments, OIDC client secrets, and passwords) are kept encrypted inside `secrets.yaml` using nested YAML groups:

```yaml
cloudflare:
  credentials: "..."
  origin-ca: "..."
traefik:
  origin-cert: "..."
  origin-key: "..."
searx:
  env: "..."
# ...
```

Compile-time parameters (such as `domain`, `tunnelId`, and `hostId`) are configured in plaintext inside [`modules/common/settings.nix`](../common/settings.nix).

---

## What to Commit

✅ **Safe**: `modules/secrets/secrets.yaml` (encrypted), `.sops.yaml` (public keys only)

❌ **Never**: `keys.txt` (your age private key), any unencrypted secret files
