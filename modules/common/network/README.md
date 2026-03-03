# Network Services Module

This module provides all networking services including SSH access, local hostname resolution, and external access via
Cloudflare Tunnel and Traefik.

## Overview

This module includes:

- **SSH Server**: Secure remote access
- **mDNS/Avahi**: Local hostname resolution (`.local` domains)
- **Traefik**: Reverse proxy for services
- **Cloudflare Tunnel**: Secure external access with mTLS

---

## Table of Contents

1. [SSH Configuration](#ssh-configuration)
2. [mDNS/Avahi (Local Hostname Resolution)](#mdnsavahi-local-hostname-resolution)
3. [Cloudflare Tunnel + Traefik Setup](#cloudflare-tunnel--traefik-setup)
4. [Required Certificates](#required-certificates)
5. [Adding New Services](#adding-new-services)

---

## Module Structure

```
modules/common/network/
├── default.nix       # SSH + mDNS configuration + imports
├── traefik.nix       # Traefik reverse proxy configuration
├── cloudflared.nix   # Cloudflare Tunnel configuration
└── README.md         # This file
```

**What each file does:**

| File              | Purpose                                                   |
|-------------------|-----------------------------------------------------------|
| `default.nix`     | SSH server, mDNS/Avahi, and imports other network modules |
| `traefik.nix`     | Reverse proxy with mTLS, dashboard, middleware            |
| `cloudflared.nix` | Cloudflare Tunnel for secure external access              |

---

## SSH Configuration

### What's Configured

```nix
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "no";           # Root login disabled
    PasswordAuthentication = true;    # Password auth enabled
  };
};
```

### Security Settings

- **Root login disabled** - Must use regular user account
- **SSH key authentication** - Configured per-user in `configuration.nix`
- **Password authentication enabled** - For initial setup and recovery

### Connecting via SSH

```bash
# Using IP address
ssh hlamnix@192.168.100.194

# Using hostname (after mDNS is enabled)
ssh hlamnix@playground.local
```

### Adding SSH Keys

SSH keys are configured per-user in [hosts/playground/configuration.nix](../../../hosts/playground/configuration.nix):

```nix
users.users.hlamnix = {
  openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3Nza... your-key-here"
  ];
};
```

---

## mDNS/Avahi (Local Hostname Resolution)

### What's Configured

```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;  # Enable mDNS for IPv4
  publish = {
    enable = true;          # Publish services
    addresses = true;       # Publish IP address
    domain = true;          # Publish domain
    hinfo = true;           # Publish host info
    userServices = true;    # Allow user services
    workstation = true;     # Publish as workstation
  };
};
```

### What It Does

Enables **hostname-based access** on your local network without needing DNS configuration:

```bash
# Instead of remembering IP addresses:
ssh hlamnix@192.168.100.194

# Use the hostname:
ssh hlamnix@playground.local

# Works for nixos-rebuild too:
nixos-rebuild switch --target-host hlamnix@playground.local ...
```

### How It Works

- **mDNS** (Multicast DNS) allows devices to discover each other on local networks
- **Avahi** is the Linux implementation (like Apple's Bonjour)
- Your system broadcasts its hostname as `<hostname>.local`
- Works automatically - no router/DNS configuration needed

### Requirements

**On macOS (your machine):**

- Built-in support (Bonjour) - works out of the box

**On Linux clients:**

```bash
# Ubuntu/Debian
sudo apt install avahi-daemon libnss-mdns

# Arch
sudo pacman -S avahi nss-mdns
```

**On Windows clients:**

- Install Bonjour Print Services or iTunes (includes Bonjour)
- Or just use IP addresses

### Testing

```bash
# Test hostname resolution
ping playground.local

# Should respond with your VM's IP (e.g., 192.168.100.194)
```

### Troubleshooting

**Can't resolve .local hostname:**

1. Check Avahi is running:
   ```bash
   ssh hlamnix@<ip>
   systemctl status avahi-daemon
   ```

2. Ensure `.local` suffix:
   ```bash
   ping playground.local  # Not just "playground"
   ```

3. Wait 30 seconds after boot for Avahi to broadcast

**Works from Mac but not Linux:**

Install mDNS support and check `/etc/nsswitch.conf`:

```
hosts: files mdns4_minimal [NOTFOUND=return] dns
```

---

## Cloudflare Tunnel + Traefik Setup

### Architecture

```
Internet → Cloudflare Tunnel (cloudflared) → Traefik (HTTPS:443) → Services
                   ↓ mTLS verification
            Cloudflare Origin CA Certificate
```

## Required Certificates

Cloudflare mTLS requires **THREE different certificates**:

### 1. Origin Certificate (What Traefik presents to Cloudflare)

This is YOUR certificate that **Traefik presents** to prove it's the legitimate origin server.

**How to get it:**

1. Go to https://dash.cloudflare.com
2. Select your domain → SSL/TLS → Origin Server
3. Click "Create Certificate"
4. Choose:
    - **Key type**: RSA (2048)
    - **Hostnames**: `yourdomain.com` and `*.yourdomain.com`
    - **Certificate Validity**: 15 years
5. Copy **BOTH**:
    - Origin Certificate (the certificate)
    - Private Key (the key)

**Add to secrets:**

```sh
sops secrets/secrets.yaml

# Add both entries:
traefik-origin-cert: |
  -----BEGIN CERTIFICATE-----
  [your origin certificate here - multiple lines]
  -----END CERTIFICATE-----

traefik-origin-key: |
  -----BEGIN PRIVATE KEY-----
  [your origin private key here - multiple lines]
  -----END PRIVATE KEY-----
```

**Deployed to:**

- Certificate: `/var/lib/traefik/certs/origin.crt`
- Private Key: `/var/lib/traefik/certs/origin.key`

### 2. Cloudflare Authenticated Origin Pull CA (What Traefik uses to verify Cloudflare)

This is **Cloudflare's public CA certificate** that Traefik uses to verify the connecting client is actually Cloudflare.

**How to get it:**

```sh
curl https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem
```

**Add to secrets:**

```sh
sops secrets/secrets.yaml

# Add this entry:
cloudflare-origin-ca: |
  -----BEGIN CERTIFICATE-----
  [Cloudflare's Origin Pull CA certificate here]
  -----END CERTIFICATE-----
```

**Deployed to:** `/var/lib/cloudflared/origin-ca.pem`

### 3. Cloudflared Tunnel Credentials

Already configured in `secrets/secrets.yaml` as `cloudflared-credentials`.

## Understanding the mTLS Flow

Here's how the certificates work together:

```
┌─────────────┐                  ┌─────────────┐                  ┌─────────────┐
│  Cloudflare │                  │   Traefik   │                  │   Service   │
│   Tunnel    │                  │             │                  │             │
└─────────────┘                  └─────────────┘                  └─────────────┘
       │                                │                                │
       │ 1. TLS Handshake Start         │                                │
       │───────────────────────────────>│                                │
       │                                │                                │
       │ 2. Traefik sends certificate   │                                │
       │    (origin.crt + origin.key)   │                                │
       │<───────────────────────────--──│                                │
       │                                │                                │
       │ 3. Cloudflare sends its cert   │                                │
       │───────────────────────────────>│                                │
       │                                │                                │
       │ 4. Traefik verifies using      │                                │
       │    origin-ca.pem (CF's CA)     │                                │
       │                                │                                │
       │ 5. mTLS Established            │                                │
       │<══════════════════════════════>│                                │
       │                                │ 6. Proxies to service          │
       │                                │───────────────────────────────>│
```

**Certificate Purposes:**

- `origin.crt` + `origin.key`: **Traefik's identity** (proves Traefik is the real origin)
- `origin-ca.pem`: **Cloudflare's CA** (allows Traefik to verify Cloudflare's client certificate)

## Configuration Flow

### 1. Cloudflared Configuration

- **File**: `modules/common/network/cloudflared.nix`
- **Tunnel ID**: Configured in `modules/common/local.nix`
- **Ingress**: Routes `*.yourdomain` → `https://localhost:443` (Traefik)
- **mTLS**: Uses `/var/lib/cloudflared/origin-ca.pem` to verify Traefik's certificate

### 2. Traefik Core Configuration

- **File**: `modules/common/network/traefik.nix`
- **Contains**: Core configuration only
    - Entry Points (HTTP :80 → HTTPS :443)
    - Shared middlewares (security-headers, rate-limit, dashboard-auth)
    - Dashboard router
    - TLS/mTLS configuration
- **Does NOT contain**: Service-specific routers/middlewares/services

### 3. Service-Specific Configuration

Services are self-contained in their own directories under `modules/containers/`:

- **Example**: `modules/containers/myservice/`
    - `container.nix` - Container definition (10.0.0.x:port)
    - `traefik.nix` - Service-specific Traefik config (router, middleware, backend)
    - `default.nix` - Imports both + DNS entry
- **Public URL**: `https://myservice.yourdomain`
- **Internal**: Accessible at `http://myservice:port` from host

## Setup Steps

### Step 0: Configure Your Local Settings

Edit `modules/common/local.nix` with your values:

```nix
{
  domain = "yourdomain.com";           # Your domain name
  tunnelId = "your-tunnel-id-here";    # From Cloudflare dashboard
}
```

**Note**: This file is tracked by git. When forking this repo, simply edit these values for your own setup.

### Step 1: Add All Certificates to Secrets

```sh
sops secrets/secrets.yaml
```

Add **three** certificate entries:

```yaml
# 1. Your origin certificate (Traefik's identity)
traefik-origin-cert: |
  -----BEGIN CERTIFICATE-----
  [your origin certificate from Cloudflare dashboard]
  -----END CERTIFICATE-----

# 2. Your origin private key (Traefik's private key)
traefik-origin-key: |
  -----BEGIN PRIVATE KEY-----
  [your origin private key from Cloudflare dashboard]
  -----END PRIVATE KEY-----

# 3. Cloudflare's Authenticated Origin Pull CA (to verify Cloudflare)
cloudflare-origin-ca: |
  -----BEGIN CERTIFICATE-----
  [Cloudflare's Origin Pull CA - get from their docs]
  -----END CERTIFICATE-----
```

**Note**: All secrets are already declared in `modules/common/secrets.nix` and will be automatically placed at the
correct locations with proper ownership and permissions.

### Step 2: Deploy

```sh
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#playground \
  --target-host hlamnix@192.168.100.194 \
  --build-host hlamnix@192.168.100.194 \
  --sudo \
  --ask-sudo-password
```

### Step 3: Verify

1. **Check cloudflared status**:
   ```sh
   sudo systemctl status cloudflared-tunnel-<your-tunnel-id>
   ```

2. **Check Traefik status**:
   ```sh
   sudo systemctl status traefik
   sudo journalctl -u traefik -f
   ```

3. **Verify all certificates are deployed**:
   ```sh
   # Traefik's origin certificate and key
   sudo ls -la /var/lib/traefik/certs/
   # Should show: origin.crt, origin.key
   
   # Cloudflare's CA certificate
   sudo ls -la /var/lib/cloudflared/origin-ca.pem
   
   # Check permissions (should be 0400, owned by traefik)
   sudo stat /var/lib/traefik/certs/origin.crt
   ```

4. **Test service access**:
   ```sh
   curl -I https://myservice.yourdomain.com
   curl -I https://traefik.yourdomain.com
   ```

5. **Access Traefik Dashboard**:
    - URL: https://traefik.yourdomain.com
    - User: `traefik-cloudflared`
    - Password: (configured in Traefik config)

## Troubleshooting

### TLS handshake failures or "certificate signed by unknown authority"

**Symptom**: Cloudflare Tunnel can't connect to Traefik, or you see certificate errors in logs.

**Possible causes:**

1. Missing or incorrect origin certificate/key
2. Missing or incorrect Cloudflare Origin Pull CA
3. Wrong file permissions

**Fix**:

```sh
# Verify all certificates exist
sudo ls -la /var/lib/traefik/certs/
# Should show: origin.crt (your cert), origin.key (your key)

sudo ls -la /var/lib/cloudflared/origin-ca.pem
# Should exist and be readable by traefik

# Check permissions (should be 0400, owned by traefik)
sudo stat /var/lib/traefik/certs/origin.crt
sudo stat /var/lib/traefik/certs/origin.key
sudo stat /var/lib/cloudflared/origin-ca.pem

# Verify cert content (should show BEGIN CERTIFICATE)
sudo -u traefik cat /var/lib/traefik/certs/origin.crt | head -1
```

### Cloudflared can't verify Traefik certificate

- **Error**: `x509: certificate signed by unknown authority`
- **Cause**: Missing or incorrect `cloudflare-origin-ca` certificate
- **Fix**: Ensure `origin-ca.pem` contains Cloudflare's Origin Pull CA, not your origin certificate
- **Get it**: `curl https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem`

### Traefik can't find routes

- **Check service config**: Routes are defined in `modules/containers/<service>/traefik.nix` for each service
- **Check core config**: Core Traefik config is in `modules/common/network/traefik.nix`
- **Check logs**: `sudo journalctl -u traefik -n 50`
- **Verify service**: `sudo systemctl status traefik`

### Service returns 404 or 502

- **Check container**: `machinectl list | grep myservice`
- **Check container networking**: `ping -c 1 10.0.0.x`
- **Test direct access**: `curl http://10.0.0.x:port` (from host)

### Can't access from internet

- **Check DNS**: Ensure `*.yourdomain` points to your Cloudflare Tunnel
- **Check Cloudflare dashboard**: Tunnel status should be "Healthy"
- **Check firewall**: Ports 80 and 443 should be open on the host

## Adding New Services

Services are modular and self-contained. To add a new service:

### 1. Create Service Directory

```bash
mkdir -p modules/containers/myservice
```

### 2. Create `container.nix`

```nix
{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  containers.myservice = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.3";  # Next available IP

    config = { pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 8080 ];
      
      services.myservice = {
        enable = true;
        # ... service configuration
      };

      system.stateVersion = "26.05";
    };
  };
}
```

### 3. Create `traefik.nix`

```nix
{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
      # Service-specific middleware (optional)
      middlewares = {
        myservice-headers = {
          headers = {
            sslRedirect = true;
            frameDeny = true;
          };
        };
      };

      # Router
      routers = {
        myservice = {
          rule = "Host(`myservice.${vars.domain}`)";
          entryPoints = [ "https" ];
          service = "myservice";
          tls = {};
          middlewares = [ "security-headers" ];  # Use shared middleware
        };
      };

      # Backend service
      services = {
        myservice = {
          loadBalancer = {
            servers = [
              { url = "http://myservice:8080"; }
            ];
            passHostHeader = true;
          };
        };
      };
    };
  };
}
```

### 4. Create `default.nix`

```nix
# MyService Module

{ ... }:
{
  imports = [
    ./container.nix
    ./traefik.nix
  ];

  # DNS entry for internal resolution
  networking.hosts = {
    "10.0.0.3" = [ "myservice" ];
  };
}
```

### 5. Import in `modules/containers/default.nix`

```nix
imports = [
  ./service-a
  ./myservice  # Add this line - folder import
];
```

### 6. Deploy

```bash
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#playground \
  --target-host hlamnix@<ip> \
  --build-host hlamnix@<ip> \
  --sudo \
  --ask-sudo-password
```

See [modules/containers/README.md](../../containers/README.md) for detailed documentation on the modular service
structure.

## Security Notes

- All traffic between Cloudflare and Traefik is encrypted (HTTPS + mTLS)
- mTLS verification is enabled - only Cloudflare can connect to Traefik
- Secrets are encrypted with sops-nix and never committed as plaintext
- Traefik dashboard is protected with basic authentication
- Internal services are isolated on private network (10.0.0.0/24)
- HTTP automatically redirects to HTTPS
