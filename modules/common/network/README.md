# Network Services

SSH, mDNS/Avahi, Traefik reverse proxy, and Cloudflare Tunnel.

## Module Structure

| File              | Purpose                                                        |
|-------------------|----------------------------------------------------------------|
| `default.nix`     | SSH server, mDNS/Avahi, imports traefik + cloudflared          |
| `traefik.nix`     | Core Traefik: entrypoints, mTLS, shared middlewares, dashboard |
| `cloudflared.nix` | Cloudflare Tunnel ingress → Traefik :443                       |

---

## SSH

```nix
services.openssh = {
  enable = true;
  settings = { PermitRootLogin = "no"; PasswordAuthentication = true; };
};
```

SSH keys are set per-user in [
`hosts/playground/configuration.nix`](../../../hosts/playground/configuration.nix)
under `users.users.hlamnix.openssh.authorizedKeys.keys`.

---

## mDNS / Avahi

Enables `playground.local` hostname resolution on the local network — no DNS config needed.

```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;
  publish = { enable = true; addresses = true; domain = true; workstation = true; };
};
```

```bash
ssh hlamnix@playground.local
nixos-rebuild switch --target-host hlamnix@playground.local ...
```

Linux clients need `avahi-daemon` + `libnss-mdns`. macOS has built-in Bonjour support.

---

## Cloudflare Tunnel + Traefik

### Architecture

```
Internet → Cloudflare Tunnel (cloudflared) → Traefik (HTTPS :443) → Containers (10.0.0.x)
                         ↓
              mTLS using origin-ca.pem
```

### Required Certificates

Three certificates are involved:

#### 1. Origin Certificate — Traefik's identity, presented to Cloudflare

1. Cloudflare Dashboard → your domain → SSL/TLS → Origin Server → **Create Certificate**
2. Hostnames: `yourdomain.com`, `*.yourdomain.com` · Validity: 15 years · Key: RSA 2048
3. Copy both the **Origin Certificate** and **Private Key**

```bash
sops modules/secrets/secrets.yaml
# Add:
#   traefik:
#     origin-cert: | <certificate>
#     origin-key:  | <private key>
```

Deployed to: `/var/lib/traefik/certs/origin.crt` and `/var/lib/traefik/certs/origin.key` (owner:
`traefik`, 0400)

#### 2. Cloudflare Authenticated Origin Pull CA — used by Traefik to verify Cloudflare

```bash
curl https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem
sops modules/secrets/secrets.yaml
# Add:
#   cloudflare:
#     origin-ca: | <certificate>
```

Deployed to: `/var/lib/cloudflared/origin-ca.pem`

#### 3. Cloudflare Tunnel Credentials

Stored as `cloudflare/credentials` in `modules/secrets/secrets.yaml`. Get the JSON from
Cloudflare Dashboard → Zero Trust → Networks → Tunnels → your tunnel → Configure.

### mTLS Flow

```
Cloudflare sends its cert  →  Traefik verifies with origin-ca.pem     ✓
Traefik sends origin.crt   →  Cloudflare verifies against its own CA   ✓
mTLS established → request proxied to container
```

### Traefik Configuration

- **Core** ([`traefik.nix`](traefik.nix)): entrypoints (HTTP :80 → HTTPS :443),
  `requireCloudflareMTLS` TLS option, shared middlewares `security-headers` + `rate-limit`,
  dashboard router
- **Per-service**: Traefik routing is automatically managed by `container-frame.nix` for every
  service defined via `hlamlab.services.<name>`. It maps `Host(\`<domainPrefix>.<domain>\`)` to the
  container.
    - You can override `traefik.rule` or disable routing entirely (`traefik.enable = false`) in the
      service configuration.
- **Dashboard**: `https://traefik.yourdomain` (basic auth); logs at `/var/log/traefik/`

### Cloudflared Configuration

- Tunnel ID and Domain from `modules/secrets/secrets.yaml` (keys `cloudflare/tunnel-id` and
  `cloudflare/domain`)
- Ingress: `*.yourdomain` → `https://localhost:443`
- mTLS CA: `/var/lib/cloudflared/origin-ca.pem`

---

## Troubleshooting

**TLS handshake / "certificate signed by unknown authority"**

```bash
sudo ls -la /var/lib/traefik/certs/         # origin.crt + origin.key must exist
sudo ls -la /var/lib/cloudflared/origin-ca.pem
sudo stat /var/lib/traefik/certs/origin.crt  # 0400, owner traefik
```

**Cloudflared: `x509: certificate signed by unknown authority`**
— `origin-ca.pem` must be Cloudflare's Origin Pull CA, not your origin cert.
Re-fetch: `curl https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem`

**Traefik 404 / 502**

```bash
sudo journalctl -u traefik -n 50
machinectl list                  # container running?
curl http://10.0.0.x:port        # direct test from host
```

**Can't access from internet**
— Verify `*.yourdomain` points to your Cloudflare Tunnel in DNS.
— Cloudflare Dashboard → Zero Trust → Tunnels → tunnel should be "Healthy".
