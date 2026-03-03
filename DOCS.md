# Documentation Overview

This NixOS homelab configuration includes comprehensive documentation to help you deploy, configure, and maintain your
infrastructure.

## 📚 Documentation Structure

### Getting Started

- **[README.md](README.md)** - Main documentation covering:
    - Repository structure and layout
    - Prerequisites and initial setup
    - Service descriptions (Traefik, Cloudflare Tunnel)
    - Container management
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

- **[modules/containers/README.md](modules/containers/README.md)** - Container management:
    - Container structure and networking
    - Daily operations (start, stop, login, logs)
    - Adding new service containers
    - Best practices

- **[modules/common/network/README.md](modules/common/network/README.md)** - Network services:
    - Cloudflare Tunnel + Traefik integration
    - mTLS configuration
    - Adding new services behind Traefik

- **[modules/common/zfs/README.md](modules/common/zfs/README.md)** ZFS storage:
    - Declarative dataset management with disko-zfs
    - Automatic snapshot scheduling
    - ZFS scrubbing and monitoring
    - Management commands and best practices
    - Compression, quotas, and reservations
    - Adding new service containers
    - Best practices

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

### Manage Containers

```bash
# See modules/containers/README.md
machinectl list
sudo nixos-container root-login <name>
```

### Add a New Service

1. Create container module in `modules/containers/`
2. Add DNS entry in `modules/containers/default.nix`
3. Add Traefik router in `modules/common/traefik.nix`
4. Deploy

Full details in [modules/common/network/README.md](modules/common/network/README.md) → "Adding New Services"

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

See [modules/secrets/README.md](modules/secrets/README.md#secrets-vs-configuration-variables) → "Secrets vs
Configuration Variables" for details.

## 🎯 Document Purpose Guide

| Document                         | Use When                                                                |
|----------------------------------|-------------------------------------------------------------------------|
| README.md                        | Setting up new hosts, deploying changes, general reference              |
| modules/common/network/README.md | Configuring Cloudflare Tunnel, adding services, troubleshooting routing |
| modules/secrets/README.md        | Managing encrypted secrets, setting up sops-nix                         |
| modules/containers/README.md     | Working with NixOS containers, container troubleshooting                |

## 💡 Tips

- All documentation uses `yourdomain` as a placeholder - replace with your actual domain
- Container IPs start at 10.0.0.2 and increment for each service
- Always test with `--dry-run` first when making major configuration changes
- Check service logs with `journalctl -u <service-name> -f`

## 🔄 Keeping Documentation Updated

When adding new features:

1. Update the relevant subsystem README (network/, secrets/)
2. Add to main README.md if it affects general usage
3. Update modules/common/network/README.md if it involves routing/services
4. Keep this DOCS.md overview in sync
