{ config, ... }:
let
  settings = config.hlamlab.settings;
  svc = config.hlamlab.services;
in
{
  hlamlab.services.lldap = {
    ip = "10.0.0.6";
    port = 3000;

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

    containerConfig = { lib, config, ... }: {
      networking.firewall.allowedTCPPorts = [ 3890 ];

      services.lldap = {
        enable = true;
        settings = {
          ldap_host = "0.0.0.0";
          ldap_port = 3890;
          http_host = "0.0.0.0";
          http_port = svc.lldap.port;
          http_url = svc.lldap.baseUrl;
          ldap_base_dn = settings.ldapBaseDn;
          jwt_secret_file = config.sops.secrets.lldap-jwt-secret.path;
          ldap_user_email = "admin@${settings.domain}";
          ldap_user_dn = "admin";
          ldap_user_pass_file = config.sops.secrets.lldap-user-pass.path;
          force_ldap_user_pass_reset = "always";
          database_url = "sqlite:///var/lib/lldap/users.db?mode=rwc";
        };
      };

      systemd.services.lldap.serviceConfig = {
        ReadWritePaths = [ "/var/lib/lldap" ];
        DynamicUser = lib.mkForce false;
      };
    };
  };

}
