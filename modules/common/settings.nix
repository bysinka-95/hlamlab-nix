{ lib, config, ... }:
let
  cfg = config.hlamlab.settings;
in
{
  options.hlamlab.settings = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "Your actual domain name (e.g., 'yourdomain.com')";
    };

    tunnelId = lib.mkOption {
      type = lib.types.str;
      description = "Your Cloudflare Tunnel ID from dashboard";
    };

    hostId = lib.mkOption {
      type = lib.types.str;
      description = "Your ZFS host ID (8 hex characters)";
    };

    lanInterface = lib.mkOption {
      type = lib.types.str;
      default = "ens18";
      description = ''
        The host's LAN NIC: containers' internet egress leaves through it, and
        it is the only interface SSH and mDNS answer on. A wrong value cuts SSH
        (deploy-rs' magic rollback then reverts the deploy).
      '';
    };

    lanAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "192.168.1.10";
      description = ''
        The host's IPv4 address on the LAN (reserve it in the DHCP settings of the router).
        If set and Blocky is enabled, Blocky answers the domain and its
        subdomains with this address, and Traefik's 443 opens on the LAN, so
        devices at home reach the services without Cloudflare.
      '';
    };

    ldapBaseDn = lib.mkOption {
      type = lib.types.str;
      description = "LDAP base DN. Defaults to derived domain (e.g., 'dc=yourdomain,dc=com')";
    };
  };

  config = {
    # Default ldapBaseDn derived from domain (only if domain is set)
    hlamlab.settings.ldapBaseDn = lib.mkIf (cfg.domain != "") (lib.mkDefault (
      builtins.concatStringsSep "," (map (p: "dc=${p}") (lib.splitString "." cfg.domain))
    ));
  };
}
