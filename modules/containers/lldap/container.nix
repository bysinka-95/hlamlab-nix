{ config, ... }:
let
  vars = import ../../common/local.nix;
in
{
  containers.lldap = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.6";

    bindMounts = {
      "/var/lib/lldap" = {
        hostPath = "/var/lib/services/lldap";
        isReadOnly = false;
      };
      "/run/secrets/lldap-jwt-secret" = {
        hostPath = config.sops.secrets.lldap-jwt-secret.path;
        isReadOnly = true;
      };
      "/run/secrets/lldap-user-pass" = {
        hostPath = config.sops.secrets.lldap-lldap-user-pass.path;
        isReadOnly = true;
      };
    };

    config = { lib, pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 3890 3000 ];
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

      environment.systemPackages = with pkgs; [ lldap ];

      services.lldap = {
        enable = true;
        environmentFile = null; # We'll use specific settings
        settings = {
          ldap_host = "0.0.0.0";
          ldap_port = 3890;
          http_host = "0.0.0.0";
          http_port = 3000;
          http_url = "https://lldap.${vars.domain}";
          ldap_base_dn = vars.ldapBaseDn;
          jwt_secret_file = "/run/secrets/lldap-jwt-secret";
          ldap_user_email = "admin@${vars.domain}";
          ldap_user_dn = "admin";
          ldap_user_pass_file = "/run/secrets/lldap-user-pass";
          force_ldap_user_pass_reset = "always";
          database_url = "sqlite:///var/lib/lldap/users.db?mode=rwc";
        };
      };

      # We need to ensure that lldap service runs with write access to /var/lib/lldap
      systemd.services.lldap.serviceConfig = {
        ReadWritePaths = [ "/var/lib/lldap" ];
        DynamicUser = lib.mkForce false;
        StateDirectory = lib.mkForce "";
        User = "lldap";
        Group = "lldap";
      };

      # Define static user/group for lldap to match host permissions
      users.users.lldap = {
        isSystemUser = true;
        group = "lldap";
        uid = 901;
      };
      users.groups.lldap = {
        gid = 901;
      };

      system.stateVersion = "26.05";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/lldap 0750 901 901 -"
  ];
}
