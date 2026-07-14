{ lib, config, ... }:
let
  vars = import ../../common/settings.nix;
in
{
  hlamlab.services.lldap = {
    ip = lib.mkDefault "10.0.0.6";
    port = lib.mkDefault 3000;
    domainPrefix = lib.mkDefault "lldap";
    storageQuota = lib.mkDefault "10G";
    storageReservation = lib.mkDefault "1G";

    bindMounts = {
      "/var/lib/lldap" = {
        hostPath = "/var/lib/services/lldap";
        isReadOnly = false;
      };
    };

    secrets = {
      lldap-jwt-secret = {
        key = "lldap/jwt-secret";
        restartUnits = [ "lldap.service" ];
      };
      lldap-user-pass = {
        key = "lldap/user-pass";
        restartUnits = [ "lldap.service" ];
      };
    };

    containerConfig = { lib, pkgs, config, ... }: {
      networking.firewall.allowedTCPPorts = [ 3890 ];

      environment.systemPackages = with pkgs; [ lldap ];

      services.lldap = {
        enable = true;
        settings = {
          ldap_host = "0.0.0.0";
          ldap_port = 3890;
          http_host = "0.0.0.0";
          http_port = 3000;
          http_url = "https://lldap.${vars.domain}";
          ldap_base_dn = vars.ldapBaseDn;
          jwt_secret_file = config.sops.secrets.lldap-jwt-secret.path;
          ldap_user_email = "admin@${vars.domain}";
          ldap_user_dn = "admin";
          ldap_user_pass_file = config.sops.secrets.lldap-user-pass.path;
          force_ldap_user_pass_reset = "always";
          database_url = "sqlite:///var/lib/lldap/users.db?mode=rwc";
        };
      };

      systemd.services.lldap.serviceConfig = {
        ReadWritePaths = [ "/var/lib/lldap" ];
        DynamicUser = lib.mkForce false;
        StateDirectory = "lldap";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/lldap 0750 root root -"
  ];
}
