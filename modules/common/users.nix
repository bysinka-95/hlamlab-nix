# Service Users Module
#
# Pre-creates system users for services to ensure they exist
# before sops-nix tries to set file ownership

{ ... }:
{
  # Cloudflared service user
  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
    description = "Cloudflare Tunnel daemon user";
  };

  users.groups.cloudflared = {};

  # Traefik service user
  users.users.traefik = {
    isSystemUser = true;
    group = "traefik";
    description = "Traefik reverse proxy user";
  };

  users.groups.traefik = {};
}

