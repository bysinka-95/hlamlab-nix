# Documentation Overview

This NixOS homelab configuration includes comprehensive documentation to help you deploy, configure, and maintain your
infrastructure.

## 📚 Documentation Structure

### Getting Started

- **[README.md](README.md)** - Main documentation covering:
    - Repository structure and layout
    - Prerequisites and initial setup
    - Service descriptions (OpenCloud, Traefik, Cloudflare Tunnel)
    - Deployment workflows
    - Troubleshooting basics

### Specific Guides

- **[modules/common/network/README.md](modules/common/network/README.md)** - Detailed setup for:
    - Cloudflare Tunnel + Traefik integration
    - mTLS configuration
    - Origin CA certificate setup
    - Adding new services behind Traefik

### Subsystem Documentation

- **[modules/secrets/README.md](modules/secrets/README.md)** - Secrets management with sops-nix:
    - Initial sops-nix setup
    - Age key generation
    - Encrypting/decrypting secrets
    - What to commit vs what to keep private

## 🚀 Quick Start Path

1. **First-time setup**: Start with [README.md](README.md) → "Initial Configuration"
2. **Configure secrets**: Follow [modules/secrets/README.md](modules/secrets/README.md)
3. **Deploy**: Use deployment commands in [README.md](README.md)
4. **Add services**: Use [modules/common/network/README.md](modules/common/network/README.md) → "Adding New Services"

## 📖 Common Tasks

### Deploy/Update Configuration

```bash
# See README.md → "Rebuild / deploy changes"
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#playground \
  --target-host hlamnix@<ip> \
  --build-host hlamnix@<ip> \
  --sudo \
  --ask-sudo-password
```

### Manage Secrets

```bash
# See modules/secrets/README.md
sops secrets/secrets.yaml
```

## 🔒 Security & Privacy

### What's Tracked (safe to commit):

- `modules/common/local.nix` - Your domain and tunnel ID (use dummy values if publishing publicly)
- All `.nix` configuration files
- Documentation files
- `.sops.yaml` (contains only public keys)

### What's Encrypted (safe to commit):

- `secrets/secrets.yaml` - All sensitive credentials (encrypted with sops-nix)

### What's Private (NEVER commit):

- `~/.config/sops/age/keys.txt` or `~/Library/Application Support/sops/age/keys.txt` - Your age private keys
- Any unencrypted secret files

See [modules/secrets/README.md](modules/secrets/README.md#secrets-vs-configuration-variables) → "Secrets vs Configuration Variables" for details.

## 🎯 Document Purpose Guide

| Document                         | Use When                                                                |
|----------------------------------|-------------------------------------------------------------------------|
| README.md                        | Setting up new hosts, deploying changes, general reference              |
| modules/common/network/README.md | Configuring Cloudflare Tunnel, adding services, troubleshooting routing |
| modules/secrets/README.md        | Managing encrypted secrets, setting up sops-nix                         |

## 💡 Tips

- All documentation uses `yourdomain` as a placeholder - replace with your actual domain
- Always test with `--dry-run` first when making major configuration changes
- Check service logs with `journalctl -u <service-name> -f`

## 🔄 Keeping Documentation Updated

When adding new features:

1. Update the relevant subsystem README (network/, secrets/)
2. Add to main README.md if it affects general usage
3. Update modules/common/network/README.md if it involves routing/services
4. Keep this DOCS.md overview in sync
