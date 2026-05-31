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

  # Authelia service user
  users.users.authelia-main = {
    isSystemUser = true;
    group = "authelia-main";
    description = "Authelia main instance user";
    uid = 900;
  };

  users.groups.authelia-main = {
    gid = 900;
  };

  # Immich service user
  users.users.immich = {
    isSystemUser = true;
    group = "immich";
    description = "Immich reverse proxy user";
    uid = 901;
  };

  users.groups.immich = {
    gid = 901;
  };
}

