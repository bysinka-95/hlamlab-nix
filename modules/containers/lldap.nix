{ config, ... }:
let
  settings = config.hlamlab.settings;
  svc = config.hlamlab.services;
in
{
  hlamlab.services.lldap = {
    ip = "10.0.0.6";
    port = 3000;

    # Both are read by the lldap process itself (`*_file` settings).
    secrets = {
      lldap-jwt-secret = {
        key = "lldap/jwt-secret";
        unit = "lldap.service";
      };
      lldap-user-pass = {
        key = "lldap/user-pass";
        unit = "lldap.service";
      };
      # Authelia's bind password. lldap-bootstrap (root) sets it, so no unit.
      authelia-ldap-password = {
        key = "authelia/ldap-password";
      };
    };

    containerConfig = { lib, pkgs, ... }: {
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
          jwt_secret_file = svc.lldap.secrets.lldap-jwt-secret.path;
          ldap_user_email = "admin@${settings.domain}";
          ldap_user_dn = "admin";
          ldap_user_pass_file = svc.lldap.secrets.lldap-user-pass.path;
          force_ldap_user_pass_reset = "always";
          database_url = "sqlite:///var/lib/lldap/users.db?mode=rwc";
        };
      };

      systemd.services.lldap.serviceConfig = {
        ReadWritePaths = [ "/var/lib/lldap" ];
        DynamicUser = lib.mkForce false;
      };

      # Groups the service modules grant roles by, and Authelia's read-only bind
      # user. lldap's own bootstrap script (shipped in its source) creates them
      # if missing, and leaves alone what is managed in the UI: other users,
      # memberships, other groups.
      # `admins` → Grafana server admin, Immich and OpenCloud admin.
      systemd.services.lldap-bootstrap = {
        after = [ "lldap.service" ];
        requires = [ "lldap.service" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [ curl jq jo ];
        environment = {
          LLDAP_URL = "http://localhost:${toString svc.lldap.port}";
          GROUP_CONFIGS_DIR = pkgs.writeTextDir "groups.json" (builtins.toJSON { name = "admins"; });
          USER_CONFIGS_DIR = pkgs.writeTextDir "authelia.json" (builtins.toJSON {
            id = "authelia";
            email = "authelia@${settings.domain}";
            password_file = svc.lldap.secrets.authelia-ldap-password.path;
            groups = [ "lldap_strict_readonly" ];
          });
          LLDAP_SET_PASSWORD_PATH = "${pkgs.lldap}/bin/lldap_set_password";
        };
        script = ''
          LLDAP_ADMIN_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/lldap-user-pass")" \
            ${pkgs.bash}/bin/bash ${pkgs.lldap.src}/scripts/bootstrap.sh
        '';
        serviceConfig = {
          Type = "oneshot";
          # The admin password, from the container's own credentials.
          LoadCredential = [ "lldap-user-pass" ];
        };
      };
    };
  };

}
