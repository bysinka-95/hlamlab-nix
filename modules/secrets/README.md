# Secrets Management with sops-nix

This directory contains encrypted secrets managed by sops-nix.

## Initial Setup

1. **Get the host's age public key** (after first deploy):
   ```sh
   ssh hlamnix@<playground-ip> "sudo cat /var/lib/sops-nix/key.txt | grep 'public key:' | cut -d: -f2 | tr -d ' '"
   ```
   Or convert from the host SSH key:
   ```sh
   ssh hlamnix@<playground-ip> "sudo ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"
   ```

2. **Create `.sops.yaml` in repo root**:
   ```yaml
   keys:
     - &admin_YOUR_KEY age1...  # Your personal age key (from ssh-to-age)
     - &playground age1...       # Host's age key from step 1
   creation_rules:
     - path_regex: secrets/secrets\.yaml$
       key_groups:
         - age:
             - *admin_YOUR_KEY
             - *playground
   ```

3. **Install sops locally**:
   ```sh
   nix-shell -p sops ssh-to-age
   ```

4. **Generate your personal age key** (if you don't have one):

   **Linux/NixOS:**
   ```sh
   mkdir -p ~/.config/sops/age
   ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
   ssh-to-age < ~/.ssh/id_ed25519.pub  # This is your public key for .sops.yaml
   ```

   **macOS (nix-darwin):**
   ```sh
   mkdir -p "$HOME/Library/Application Support/sops/age"
   ssh-to-age -private-key -i ~/.ssh/id_ed25519 > "$HOME/Library/Application Support/sops/age/keys.txt"
   ssh-to-age < ~/.ssh/id_ed25519.pub  # This is your public key for .sops.yaml
   ```

5. **Edit the secrets file**:
   ```sh
   sops secrets/secrets.yaml
   ```
   Replace the placeholder with your actual cloudflared credentials JSON (as a single-line string):
   ```yaml
   cloudflared-credentials: |
     {"AccountTag":"...","TunnelSecret":"...","TunnelID":"..."}
   ```

6. **Commit the encrypted file**:
   ```sh
   git add secrets/secrets.yaml .sops.yaml
   git commit -m "Add encrypted cloudflared credentials"
   ```

## Usage

- **Edit secrets**: `sops secrets/secrets.yaml`
- **Add new secrets**: Edit `modules/common/secrets.nix` to declare the secret, then add it to `secrets.yaml` with sops
- **Rotate keys**: Update `.sops.yaml`, then run `sops updatekeys secrets/secrets.yaml`

## Secrets vs Configuration Variables

### 🔒 **Secrets** (In `secrets/secrets.yaml`, encrypted with sops-nix):

- `cloudflared-credentials` - Tunnel authentication credentials (truly secret)
- `cloudflare-origin-ca` - Origin CA certificate for mTLS (sensitive)
- `traefik-origin-cert` - Your origin certificate (sensitive)
- `traefik-origin-key` - Your origin private key (sensitive)
- Future passwords, API keys, tokens

### 📝 **Configuration Variables** (In `modules/common/local.nix`):

- `domain` - Your domain name (e.g., `yourdomain.com`)
- `tunnelId` - Your Cloudflare Tunnel ID
- Tracked by git for convenience
- Not truly secret (domain is in DNS, tunnel ID is just an identifier)
- Use dummy placeholder values when publishing publicly (e.g., "example.com", "00000000-0000-0000-0000-000000000000")

**Why keep domain/tunnel ID in local.nix instead of secrets?**

- They're not truly secret (domain is in DNS, tunnel ID is just an identifier)
- But you may want them private when publishing your config
- Easier to manage (no encryption needed for non-sensitive values)
- Clear separation: encrypted secrets vs configuration variables
- Using dummy values when public keeps your actual values private while maintaining a working example

## What to commit to git

✅ **SAFE TO COMMIT:**

- `secrets/secrets.yaml` - Encrypted secrets file (safe to commit)
- `.sops.yaml` - Contains only public age keys (safe to commit)
- `modules/common/local.nix` - Configuration variables (tracked by default)

❌ **NEVER COMMIT:**

- `~/.config/sops/age/keys.txt` - Your private age key on Linux (keep it local only)
- `$HOME/Library/Application Support/sops/age/keys.txt` - Your private age key on macOS (keep it local only)
- Any unencrypted `.yaml` files with plaintext secrets
- Private keys of any kind

## Important Notes

- `.sops.yaml` contains **only public keys** - it's metadata that tells sops who can decrypt the secrets
- `secrets.yaml` is **fully encrypted** - even though you commit it, only holders of the private keys can decrypt it
- The host automatically decrypts secrets on boot using its SSH host key (`/etc/ssh/ssh_host_ed25519_key`)
- Secrets are only readable by the specified owner (e.g., `cloudflared` user) after decryption
