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

    ldapBaseDn = lib.mkOption {
      type = lib.types.str;
      description = "LDAP base DN. Defaults to derived domain (e.g., 'dc=yourdomain,dc=com')";
    };
  };

  config = {
    # Default ldapBaseDn derived from domain (only if domain is set)
    hlamlab.settings.ldapBaseDn = lib.mkIf (cfg.domain != "") (lib.mkDefault (
      let
        parts = builtins.filter (x: builtins.typeOf x == "string" && x != "") (builtins.split "\\." cfg.domain);
      in
      builtins.concatStringsSep "," (map (p: "dc=${p}") parts)
    ));
  };
}
