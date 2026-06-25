# Service Users Module
#
# Pre-creates system users for services to ensure they exist
# before sops-nix tries to set file ownership

{ lib, ... }:
{
  # Cloudflared service user
  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
    description = "Cloudflare Tunnel daemon user";
  };

  users.groups.cloudflared = { };

  # Traefik service user
  users.users.traefik = {
    isSystemUser = true;
    group = "traefik";
    description = "Traefik reverse proxy user";
  };

  users.groups.traefik = { };

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

  # LLDAP service user
    users.users.lldap = {
      isSystemUser = true;
      group = "lldap";
      description = "LLDAP service user";
      uid = 901;
    };

    users.groups.lldap = {
      gid = 901;
    };

  # Immich service user
  users.users.immich = {
    isSystemUser = true;
    group = "immich";
    description = "Immich service user";
    uid = 902;
  };

  users.groups.immich = {
    gid = 902;
  };

  # Opencloud service user
  users.users.opencloud = {
    isSystemUser = true;
    group = "opencloud";
    description = "Opencloud service user";
    uid = 903;
  };

  users.groups.opencloud = {
    gid = 903;
  };

  # Vaultwarden service user
  users.users.vaultwarden = {
    isSystemUser = true;
    group = "vaultwarden";
    description = "Vaultwarden service user";
    uid = 904;
  };

  users.groups.vaultwarden = {
    gid = 904;
  };
}
