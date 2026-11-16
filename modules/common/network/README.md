# Network Services

SSH, mDNS/Avahi, Traefik reverse proxy, and Cloudflare Tunnel.

## Module Structure

| File              | Purpose                                                        |
|-------------------|----------------------------------------------------------------|
| `default.nix`     | SSH server, mDNS/Avahi, imports traefik + cloudflared          |
| `traefik.nix`     | Core Traefik: entrypoint, LE certificate, middlewares, dashboard |
| `cloudflared.nix` | Cloudflare Tunnel ingress → Traefik :443                       |
| `crowdsec.nix`    | CrowdSec engine: Traefik access log + Authelia journal, LAPI 127.0.0.1:8180 |
| `traefik-plugins/realip/` | Local Traefik plugin: client IP from `CF-Connecting-IP` (Go, `go test`) |

---

## SSH

```nix
services.openssh = {
  enable = true;
  settings = { PermitRootLogin = "no"; PasswordAuthentication = false; };
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
```

`flake.nix` points deploy-rs at `playground.local`, so deploys depend on mDNS resolving. If it
does not (Avahi still starting, or a network that blocks mDNS), pass the IP for that run:
`nix run nixpkgs#deploy-rs -- .#playground --hostname 192.168.x.y`.

Linux clients need `avahi-daemon` + `libnss-mdns`. macOS has built-in Bonjour support.

---

## Cloudflare Tunnel + Traefik

### Architecture

```
Internet → Cloudflare Tunnel (cloudflared) → Traefik (HTTPS :443) → Containers (10.0.0.x)
```

cloudflared runs on the host and connects to Traefik over loopback. Traefik serves a public
Let's Encrypt wildcard, so cloudflared verifies it against the system roots. Containers that call
each other by public name reach the same Traefik through their gateway (`10.0.0.1`) and trust the
same certificate.

### Certificate and credentials

#### 1. Let's Encrypt wildcard — via DNS-01

Traefik obtains one certificate for `yourdomain` + `*.yourdomain` and renews it itself. DNS-01
needs no inbound port, so it works behind the tunnel. It only needs a Cloudflare API token:

1. dash.cloudflare.com → avatar → **My Profile** → **API Tokens** → **Create Token** →
   **Edit zone DNS** template.
2. Permissions: `Zone · DNS · Edit` plus `Zone · Zone · Read`. Zone Resources:
   `Include · Specific zone · yourdomain`. No IP filtering, no TTL.
3. Store it:

```bash
read -rs t; printf '%s' "$t" | jq -R . | nix run nixpkgs#sops -- set --value-stdin modules/secrets/secrets.yaml '["cloudflare"]["dns-api-token"]'; unset t
```

Traefik reads it through `CF_DNS_API_TOKEN_FILE`. The certificate is kept in
`/var/lib/traefik/acme.json`, so restarts and redeploys reuse it — reissuing on every reinstall
would hit Let's Encrypt's duplicate-certificate limit (5 per week).

#### 2. Cloudflare Tunnel Credentials

Stored as `cloudflare/credentials` in `modules/secrets/secrets.yaml`. Get the JSON from
Cloudflare Dashboard → Zero Trust → Networks → Tunnels → your tunnel → Configure.

### Traefik Configuration

- **Core** ([`traefik.nix`](traefik.nix)): the `https` entrypoint (:443) and its TLS (the
  `letsencrypt` resolver), shared `security-headers` middleware, dashboard router. Routers carry
  no `tls` block of their own — one would replace the entrypoint's TLS wholesale.
- **Per-service**: Traefik routing is automatically managed by `frame.nix` for every
  service defined via `hlamlab.services.<name>`. It maps `Host(\`<domainPrefix>.<domain>\`)` to the
  container.
    - You can disable routing entirely (`traefik.enable = false`) in the
      service configuration.
- **Client IP**: the entrypoint's `real-ip` middleware (local plugin `realip`) sets
  `X-Forwarded-For`/`X-Real-Ip` from Cloudflare's `CF-Connecting-IP`, but only for requests
  from cloudflared (loopback); from containers the header is dropped, so they cannot claim a
  client IP. Authelia, SearXNG's limiter and the apps all see the real client.
- **Dashboard**: `https://traefik.yourdomain` (Authelia 2FA, `admins` group); logs at `/var/log/traefik/`

### Cloudflared Configuration

- Tunnel ID and Domain from the host's `hlamlab.settings` configuration (keys `tunnelId` and
  `domain`).
- Ingress: `*.yourdomain` → `https://localhost:443`, verifying Traefik's certificate for
  `yourdomain` (`originServerName`).

### CrowdSec

- **Detection** ([`crowdsec.nix`](crowdsec.nix)): the engine reads Traefik's access log and
  Authelia's journal; alerts become 4h bans. The central API (community blocklist) is off, so
  nothing about the host or its visitors is sent to CrowdSec. Metrics on `:6060` for the
  prometheus container; Grafana dashboard **Crowdsec Overview**.
- **Remediation**: the `crowdsec` middleware (bouncer plugin) runs first on the `https`
  entrypoint, with AppSec virtual patching. It fails open: if CrowdSec is down, traffic passes.
  Containers (`10.0.0.0/24`) are never checked.

---

## Troubleshooting

**Banned yourself (403 everywhere from one IP)**

```bash
sudo cscli decisions list            # what, why, until when
sudo cscli decisions delete -i <ip>  # the bouncer picks it up within a minute
```

**TLS handshake / Traefik's default certificate is served**

```bash
sudo journalctl -u traefik -b | grep -i -e acme -e error   # DNS-01 progress and failures
sudo jq '.letsencrypt.Certificates[].domain' /var/lib/traefik/acme.json
echo | openssl s_client -connect localhost:443 -servername yourdomain 2>/dev/null \
  | openssl x509 -noout -issuer -ext subjectAltName
```

An ACME error naming the token usually means a missing `Zone · Zone · Read` permission or a token
scoped to a different zone.

**Traefik 404 / 502**

```bash
sudo journalctl -u traefik -n 50
machinectl list                  # container running?
curl http://10.0.0.x:port        # direct test from host
```

**Can't access from internet**
— Verify `*.yourdomain` points to your Cloudflare Tunnel in DNS.
— Cloudflare Dashboard → Zero Trust → Tunnels → tunnel should be "Healthy".
