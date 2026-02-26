# Cloudflare Tunnel + Traefik + TLS Setup

This document explains how to configure Cloudflare Tunnel with Traefik reverse proxy and mTLS authentication.

## Architecture

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

### 2. Traefik Configuration

- **File**: `modules/common/traefik.nix`
- **Entry Points**:
    - HTTP (`:80`) → Redirects to HTTPS
    - HTTPS (`:443`) → Requires Cloudflare mTLS
- **Configuration**: Native Nix via `dynamicConfigOptions` (no YAML files)
- **Routers**:
    - `traefik.yourdomain` → Traefik Dashboard (with basic auth)

### 3. Service Configuration

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
   curl -I https://opencloud.yourdomain.com
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

- **Check configuration**: Routes are defined in `modules/common/traefik.nix` under `dynamicConfigOptions`
- **Check logs**: `sudo journalctl -u traefik -n 50`
- **Verify service**: `sudo systemctl status traefik`

### Can't access from internet

- **Check DNS**: Ensure `*.yourdomain` points to your Cloudflare Tunnel
- **Check Cloudflare dashboard**: Tunnel status should be "Healthy"
- **Check firewall**: Ports 80 and 443 should be open on the host

## Adding New Services

To add a new service (e.g., `nextcloud.yourdomain`):

1. Create a new service

2. Add router and service in `modules/common/traefik.nix` under `dynamicConfigOptions`:
   ```nix
   dynamicConfigOptions = {
     http = {
       routers = {
         # ...existing routers...
         nextcloud = {
           rule = "Host(`nextcloud.${vars.domain}`)";
           entryPoints = [ "https" ];
           service = "nextcloud";
           tls = {};
           middlewares = [ "security-headers" ];
         };
       };
       
       services = {
         # ...existing services...
         nextcloud = {
           loadBalancer = {
             servers = [
               { url = "http://nextcloud:80"; }
             ];
             passHostHeader = true;
           };
         };
       };
     };
   };
   ```

3. Rebuild and deploy

## Security Notes

- ✅ All traffic between Cloudflare and Traefik is encrypted (HTTPS + mTLS)
- ✅ mTLS verification is enabled - only Cloudflare can connect to Traefik
- ✅ Secrets are encrypted with sops-nix and never committed as plaintext
- ✅ Traefik dashboard is protected with basic authentication
- ✅ Internal services are isolated on private network (10.0.0.0/24)
- ✅ HTTP automatically redirects to HTTPS
