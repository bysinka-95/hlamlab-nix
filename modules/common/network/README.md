# Network services

SSH, mDNS (Avahi), the host firewall, Traefik, Cloudflare Tunnel, CrowdSec, the host log agent
and the host exporters.

## Module structure

| File                      | Purpose                                                                    |
|---------------------------|----------------------------------------------------------------------------|
| `default.nix`             | SSH, Avahi, LAN firewall rules. Imports the other files                    |
| `traefik.nix`             | Traefik: entrypoint, Let's Encrypt certificate, middlewares, dashboard     |
| `traefik-plugins/realip/` | Local Traefik plugin: client IP from `CF-Connecting-IP` (Go, `go test`)    |
| `cloudflared.nix`         | Cloudflare Tunnel to Traefik :443                                          |
| `crowdsec.nix`            | CrowdSec engine, Traefik bouncer and AppSec. LAPI on 127.0.0.1:8180        |
| `alloy.nix`               | Host log agent and the log receiver for the containers (:3500)             |
| `alloy-config.nix`        | Alloy config that the host agent and the container agents share           |
| `exporters.nix`           | Host node_exporter (:9100) and cAdvisor (:8080)                            |

---

## SSH

```nix
services.openssh = {
  enable = true;
  settings = { PermitRootLogin = "no"; PasswordAuthentication = false; };
};
```

The SSH keys are in [`hosts/playground/configuration.nix`](../../../hosts/playground/configuration.nix)
under `users.users.hlamnix.openssh.authorizedKeys.keys`. SSH answers on `lanInterface` only.

---

## mDNS (Avahi)

Avahi publishes the name `playground.local` on the LAN, so you need no DNS record.

```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;
  settings.publish = { disable-publishing = false; publish-addresses = true; };
};
```

```bash
ssh hlamnix@playground.local
```

`flake.nix` points deploy-rs at `playground.local`, so deploys need mDNS. If the name does not
resolve (Avahi is still starting, or the network blocks mDNS), give the IP for that deploy:
`nix run nixpkgs#deploy-rs -- .#playground --hostname 192.168.x.y`.

Linux clients need `avahi-daemon` and `libnss-mdns`. macOS has Bonjour built in.

---

## Cloudflare Tunnel and Traefik

### Architecture

```
Internet → Cloudflare Tunnel (cloudflared) → Traefik (HTTPS :443) → Containers (10.0.0.x)
```

cloudflared runs on the host and connects to Traefik over loopback. Traefik serves a public
Let's Encrypt wildcard certificate, and cloudflared checks it against the system CA list. A
container that calls another service by its public name goes to the same Traefik through its
gateway (`10.0.0.1`). It trusts the same certificate.

### Certificate and credentials

#### 1. Let's Encrypt wildcard certificate through DNS-01

Traefik gets one certificate for `yourdomain` and `*.yourdomain`, and renews it. DNS-01 needs no
inbound port, so it works behind the tunnel. It needs a Cloudflare API token:

1. In dash.cloudflare.com, open your avatar, then **My Profile**, **API Tokens**,
   **Create Token**. Select the **Edit zone DNS** template.
2. Permissions: `Zone · DNS · Edit` and `Zone · Zone · Read`. Zone Resources:
   `Include · Specific zone · yourdomain`. No IP filter, no TTL.
3. Store the token:

```bash
read -rs t; printf '%s' "$t" | nix run nixpkgs#jq -- -R . | nix run nixpkgs#sops -- set --value-stdin modules/secrets/secrets.yaml '["cloudflare"]["dns-api-token"]'; unset t
```

Traefik reads the token through `CF_DNS_API_TOKEN_FILE`. It keeps the certificate in
`/var/lib/traefik/acme.json`. Restarts and deploys use the stored certificate.

A reinstall with nixos-anywhere formats the disk and deletes `acme.json`. Traefik then gets a new
certificate. Let's Encrypt allows 5 duplicate certificates per week. If you reinstall many times,
copy `acme.json` from the old host to the new host before Traefik starts. The file must have owner
`traefik` and mode `0600`.

#### 2. Cloudflare Tunnel credentials

The credentials are `cloudflare/credentials` in `modules/secrets/secrets.yaml`. To get the JSON,
open the Cloudflare dashboard, then Zero Trust, Networks, Tunnels, your tunnel, Configure.

### Traefik configuration

- **Core** ([`traefik.nix`](traefik.nix)): the `https` entrypoint (:443) and its TLS (resolver
  `letsencrypt`), the shared `security-headers` middleware and the dashboard router. Routers have
  no `tls` block. A `tls` block on a router replaces all TLS settings of the entrypoint.
- **Per service**: `frame.nix` makes a router for each service in `hlamlab.services.<name>`. The
  router sends `Host(\`<domainPrefix>.<domain>\`)` to the container. To turn routing off, set
  `traefik.enable = false` in the service module.
- **Client IP**: the `real-ip` entrypoint middleware (local plugin `realip`) sets
  `X-Forwarded-For` and `X-Real-Ip` from Cloudflare's `CF-Connecting-IP`. It does this only for
  requests from cloudflared (loopback). For requests from containers, it deletes the header, so a
  container cannot give a false client IP. Authelia, the SearXNG limiter and the apps see the real
  client.
- **Authelia checks the real request**: the plugin also sets `X-Forwarded-Host` to the real host.
  It deletes `X-Forwarded-Uri`, `-Method` and `-Prefix` from the client. Traefik's forwardAuth then
  sends the real host and path to Authelia, so a client cannot choose what Authelia checks.
- **Dashboard**: `https://traefik.yourdomain` (Authelia 2FA, `admins` group). Logs are in
  `/var/log/traefik/`.

### cloudflared configuration

- The tunnel ID and the domain come from `hlamlab.settings` (`tunnelId` and `domain`).
- Ingress: `*.yourdomain` goes to `https://localhost:443`. cloudflared checks that Traefik's
  certificate is valid for `yourdomain` (`originServerName`).

### CrowdSec

- **Detection** ([`crowdsec.nix`](crowdsec.nix)): the engine reads the Traefik access log. If
  Authelia is enabled, it also reads the Authelia journal. An alert becomes a 4h ban. The central
  API (community blocklist) is off, so the host sends no data to CrowdSec. Metrics are on `:6060`
  for the prometheus container. The Grafana dashboard is **Crowdsec Overview**.
- **Remediation**: the `crowdsec` middleware (bouncer plugin) is the first middleware on the
  `https` entrypoint. It also does AppSec virtual patching. It fails open: if CrowdSec is down,
  traffic goes through. It never checks the containers (`10.0.0.0/24`).
- **Bouncer key**: the unit `crowdsec-bouncer-register` registers the key at each CrowdSec start.
  Because the bouncer fails open, a missing key shows no errors on the sites. Check with
  `sudo -u crowdsec cscli bouncers list`: `traefik` must have a recent last pull.

---

## Troubleshooting

Run `cscli` as the `crowdsec` user. It writes the LAPI database directly.

**You banned yourself (403 on all sites from one IP)**

```bash
sudo -u crowdsec cscli decisions list            # what, why, until when
sudo -u crowdsec cscli decisions delete -i <ip>  # the bouncer reads the change within a minute
```

**TLS handshake fails, or Traefik serves its default certificate**

```bash
sudo journalctl -u traefik -b | grep -i -e acme -e error   # DNS-01 progress and failures
sudo cat /var/lib/traefik/acme.json | nix run nixpkgs#jq -- '.letsencrypt.Certificates[].domain'
curl -sv -o /dev/null --resolve yourdomain:443:127.0.0.1 https://yourdomain/ 2>&1 \
  | grep -E 'issuer:|subjectAltName'
```

An ACME error about the token usually means that `Zone · Zone · Read` is missing, or that the
token is for a different zone.

**Traefik returns 404 or 502**

```bash
sudo journalctl -u traefik -n 50
machinectl list                  # does the container run?
curl http://10.0.0.x:port        # direct test from the host
```

**The sites are not reachable from the internet**

- Check that the DNS record `*.yourdomain` points to your Cloudflare Tunnel.
- In the Cloudflare dashboard, open Zero Trust, then Tunnels. The tunnel must be "Healthy".
