# NixOS Installation Guide

Complete guide to installing this NixOS configuration on a new machine.

## Overview

This guide covers:

1. **Pre-installation**: Preparing your local machine and configuration
2. **Installation**: Running nixos-anywhere to install the system
3. **Post-installation**: Essential configuration and verification steps

**Expected time:** 30-60 minutes (depending on network speed)

---

## Prerequisites

- **Target machine**: x86_64 system
- **Network access**: Both local machine and target on same network
- **Nix installed**: On your local machine

---

## Part 1: Pre-Installation Preparation

### 1. Configure Local Variables

Edit [`modules/common/local.nix`](modules/common/local.nix) with your domain and tunnel ID:

```nix
{
  domain = "yourdomain.com";           # Your domain
  tunnelId = "your-tunnel-id-here";    # From Cloudflare dashboard
}
```

**Note:** These values can be dummy placeholders initially - you can update them later when you set up Cloudflare
Tunnel.

### 2. Generate SSH Key (if you don't have one)

```bash
# On your local machine (macOS/Linux)
ssh-keygen -t ed25519 -C "your-email@example.com"

# Display your public key
cat ~/.ssh/id_ed25519.pub
```

**Copy this public key** - you'll need it in the next step.

### 3. Add Your SSH Key to Configuration

Edit [`hosts/playground/configuration.nix`](hosts/playground/configuration.nix):

```nix
users.users.hlamnix = {
  openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3Nza... your-public-key-here"
  ];
};
```

**Security:** Your SSH public key is safe to commit to git. Never commit private keys!

### 4. Create User Password Hash

Generate a hashed password for the `hlamnix` user:

```bash
# On your local machine
nix run nixpkgs#mkpasswd -- -m sha-512

# Enter your desired password when prompted
# Copy the output hash
```

Edit [`hosts/playground/configuration.nix`](hosts/playground/configuration.nix) and update the `hashedPassword`:

```nix
users.users.hlamnix = {
  hashedPassword = "$6$rounds=656000$...";  # Paste your hash here
  // ...existing code...
};
```

**Note:** This password will be used for SSH (if key auth fails) and for `sudo` commands.

### 5. Review and Adjust Disk Configuration

Check the disk configuration in [`hosts/playground/disk-config.nix`](hosts/playground/disk-config.nix):

```bash
# View the current disk layout
cat hosts/playground/disk-config.nix
```

**Key things to verify:**

1. **Target disk device**: Default is `/dev/sda` - change if your target uses different disk (e.g., `/dev/nvme0n1`, `/dev/vda`)
2. **Disk sizes**: Adjust dataset quotas if needed:
   ```nix
   "services/opencloud" = {
     options = {
       quota = "50G";  # Adjust based on your needs
       // ...
     };
   };
   ```

**Most common adjustment** - if using VM with virtio disk:
```nix
disk = {
  main = {
    device = "/dev/vda";  # Changed from /dev/sda
    // ...existing code...
  };
};
```

### 6. Configure Container Resource Limits (Optional)

If you want to set resource limits for containers, review [`modules/containers/container-limits.nix`](modules/containers/container-limits.nix):

```bash
cat modules/containers/container-limits.nix
```

Adjust limits based on your hardware:

```nix
systemd.services."container@opencloud" = {
  serviceConfig = {
    CPUQuota = "100%";      # Adjust: 50% = half core, 200% = 2 cores
    MemoryMax = "2G";       # Adjust based on available RAM
    // ...existing code...
  };
};
```

**Note:** You can skip this step initially and configure limits later after testing your services.

### 7. Set Up Secrets Management

#### Generate Age Key

```bash
# macOS
mkdir -p ~/Library/Application\ Support/sops/age
nix run nixpkgs#age -- -generate -o ~/Library/Application\ Support/sops/age/keys.txt

# Linux
mkdir -p ~/.config/sops/age
nix run nixpkgs#age -- -generate -o ~/.config/sops/age/keys.txt
```

#### Get Your Public Key

```bash
# macOS
nix run nixpkgs#age -- -y ~/Library/Application\ Support/sops/age/keys.txt

# Linux
nix run nixpkgs#age -- -y ~/.config/sops/age/keys.txt
```

**Copy the output** - it looks like: `age1abc123...`

#### Configure .sops.yaml

Edit [`.sops.yaml`](.sops.yaml) in the repository root:

```yaml
keys:
  - &admin age1abc123...  # Your public key from above
  - &playground age1xyz789...  # Will be added after installation

creation_rules:
  - path_regex: secrets/secrets.yaml$
    key_groups:
      - age:
          - *admin
          - *playground
```

#### Initialize Secrets File

```bash
# Create initial secrets file
nix run nixpkgs#sops -- modules/secrets/secrets.yaml
```

Add **placeholder values** for now:

```yaml
# Initial secrets (update these later with real values)
cloudflared-credentials: |
  placeholder-will-be-updated-later

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
```

**Note:** You can update these with real certificates later. See [modules/common/network/README.md](modules/common/network/README.md#required-certificates) for details.

### 8. Verify Configuration

```bash
# Check for syntax errors
nix flake check

# Should pass with no errors
```

---

## Part 2: Installation

### 1. Prepare Target Machine

**Boot target machine with NixOS installer ISO:**

- Download from: https://nixos.org/download.html#nixos-iso
- Boot the installer

**Get target IP address:**

```bash
# On the target machine terminal:
ip a
# Note the IP address (e.g., 192.168.100.236)
```

**Set root password (temporary, for installation only):**

```bash
# On target machine:
sudo passwd
# Enter a simple password - only needed during installation
```

### 2. Run nixos-anywhere

From your local machine, run:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake '.#playground' \
  --generate-hardware-config nixos-generate-config ./hosts/playground/hardware-configuration.nix \
  --target-host nixos@<target-ip> \
  --build-on remote
```

**Replace `<target-ip>`** with your target machine's IP (e.g., 192.168.100.236)

**Important flags explained:**

- `--flake '.#playground'` - Which configuration to deploy
- `--generate-hardware-config` - Auto-detect hardware and save config
- `--target-host nixos@<ip>` - Where to install (default installer user is `nixos`)
- `--build-on remote` - **Critical for cross-architecture** (e.g., deploying from ARM to x86_64)

**What happens during installation:**

1. Connects to target machine via SSH
2. Partitions disk (creates ZFS pool and datasets)
3. Builds NixOS system (on remote machine if using `--build-on remote`)
4. Installs system to disk
5. Generates hardware-configuration.nix
6. Reboots into new system

### 3. Troubleshooting Installation

**SSH connection fails:**

```bash
# Ensure target is reachable
ping <target-ip>

# Test SSH manually
ssh nixos@<target-ip>
```

**Build fails on local machine (architecture mismatch):**

Use `--build-on remote` flag (already in command above). This builds on the target machine instead of locally.

**Disk errors:**

```bash
# Ensure target disk is clean
# Boot target from installer ISO and run:
sudo wipefs -a /dev/sda  # WARNING: Destroys all data!
```

---

## Part 3: Post-Installation

### 1. Get System Host Key for Secrets

After installation completes and system reboots, get the host's age key:

```bash
# SSH into the new system (use IP first time)
ssh hlamnix@<target-ip>

# Get the system's age public key
nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'

# Copy the output (starts with age1...)
```

### 2. Add Host Key to sops

On your local machine, edit [`.sops.yaml`](.sops.yaml):

```yaml
keys:
  - &admin age1abc123...  # Your key
  - &playground age1xyz789...  # Add the host key from step 1

creation_rules:
  - path_regex: secrets/secrets.yaml$
    key_groups:
      - age:
          - *admin
          - *playground
```

**Update secrets with new key:**

```bash
nix run nixpkgs#sops -- updatekeys modules/secrets/secrets.yaml
```

### 3. Set Host ID for ZFS

```bash
# SSH into the system
ssh hlamnix@<target-ip>

# Get the host ID
head -c 8 /etc/machine-id
# Output: a1b2c3d4
```

On your local machine, edit [`modules/common/zfs/default.nix`](modules/common/zfs/default.nix):

```nix
networking.hostId = "a1b2c3d4";  # Replace with output from above
```

### 4. Deploy Host ID Configuration

```bash
# From your local machine
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#playground \
  --target-host hlamnix@<target-ip> \
  --build-host hlamnix@<target-ip> \
  --sudo --ask-sudo-password
```

When prompted, enter the `hlamnix` user password (the one from `hashedPassword` in [`configuration.nix`](hosts/playground/configuration.nix)).

### 5. Verify mDNS/Hostname Resolution

After the rebuild completes, test hostname access:

```bash
# From your local machine (should work now)
ping playground.local

# Connect via hostname
ssh hlamnix@playground.local
```

**If this works**, you can now use `playground.local` instead of IP addresses for all future operations!

### 6. Update Real Secrets

If you want to enable Cloudflare Tunnel and Traefik, update the secrets with real values:

```bash
nix run nixpkgs#sops -- modules/secrets/secrets.yaml
```

See [modules/common/network/README.md](modules/common/network/README.md#required-certificates) for how to obtain:

- Cloudflare Tunnel credentials
- Traefik origin certificate
- Cloudflare Origin Pull CA

---

## Part 4: Verification

### Essential Checks

```bash
# 1. SSH access works
ssh hlamnix@playground.local

# 2. ZFS pool is healthy
zpool status

# 3. All datasets exist
zfs list

# 4. Containers are running (if configured)
machinectl list

# 5. Network services are active
systemctl status sshd
systemctl status avahi-daemon
```

### Quick System Info

```bash
# NixOS version
nixos-version

# System architecture
uname -m

# Disk usage
df -h

# ZFS compression ratio
zfs get compressratio -r tank/services
```

---

## Part 5: Next Steps

### Recommended Actions

1. **Change user password** (using the hashed password is fine, but you might want to change it):
   ```bash
   ssh hlamnix@playground.local
   passwd
   ```

2. **Update secrets with real values** (for Cloudflare Tunnel):
    - See [modules/common/network/README.md](modules/common/network/README.md)

3. **Add services**:
    - See [modules/containers/README.md](modules/containers/README.md) for adding containers

4. **Set up resource limits** (optional):
    - See [docs/RESOURCE-MANAGEMENT.md](docs/RESOURCE-MANAGEMENT.md)

5. **Configure backups**:
    - Set up ZFS replication (syncoid)
    - Configure off-site backups

### Update Workflow

From now on, deploy configuration changes with:

```bash
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#playground \
  --target-host hlamnix@playground.local \
  --build-host hlamnix@playground.local \
  --sudo --ask-sudo-password
```

---

## Troubleshooting

### Can't SSH After Installation

**Problem:** SSH connection refused or times out

**Solutions:**

1. Check system is running: ping the IP address
2. Verify SSH service: boot into rescue mode and check `systemctl status sshd`
3. Check firewall: `sudo firewall-cmd --list-all` (should allow SSH port 22)

### Hostname (.local) Not Resolving

**Problem:** `ping playground.local` fails

**Solutions:**

1. Wait 30 seconds after boot for Avahi to start
2. Check Avahi is running: `systemctl status avahi-daemon`
3. Ensure mDNS is enabled on your client (
   see [network README](modules/common/network/README.md#mdnsavahi-local-hostname-resolution))

### Secrets Decryption Fails

**Problem:** "sops metadata not found" or permission denied

**Solutions:**

1. Verify age key location:
    - macOS: `~/Library/Application Support/sops/age/keys.txt`
    - Linux: `~/.config/sops/age/keys.txt`
2. Check key is in [`.sops.yaml`](.sops.yaml): `cat .sops.yaml | grep age1`
3. Re-run `sops updatekeys modules/secrets/secrets.yaml`

### ZFS Pool Won't Import

**Problem:** System boots but ZFS pool not available

**Solutions:**

1. Check pool status: `zpool status`
2. Force import: `sudo zpool import -f tank`
3. Verify host ID is set correctly in configuration

---

## Quick Reference

### Common Commands

```bash
# Deploy configuration changes
nixos-rebuild switch --flake .#playground --target-host hlamnix@playground.local --sudo --ask-sudo-password

# Edit secrets
nix run nixpkgs#sops -- modules/secrets/secrets.yaml

# Check ZFS health
ssh hlamnix@playground.local "zpool status && zfs list"

# View system logs
ssh hlamnix@playground.local "journalctl -f"

# List containers
ssh hlamnix@playground.local "machinectl list"
```

### Useful Documentation

- **[README.md](README.md)** - Project overview and structure
- **[modules/common/zfs/README.md](modules/common/zfs/README.md)** - ZFS dataset management
- **[modules/common/network/README.md](modules/common/network/README.md)** - SSH, mDNS, Traefik, Cloudflare
- **[modules/containers/README.md](modules/containers/README.md)** - Adding and managing services
- **[modules/secrets/README.md](modules/secrets/README.md)** - Secrets management with sops-nix
