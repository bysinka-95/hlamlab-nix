{ config, inputs, ... }:
let
  vars = import ../../common/settings.nix;
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
      "/var/lib/sops-nix/key.txt" = {
        hostPath = "/var/lib/sops-nix/key.txt";
        isReadOnly = true;
      };
    };

    config = { lib, pkgs, config, ... }: {
      imports = [
        inputs.sops-nix.nixosModules.sops
      ];

      sops = {
        defaultSopsFile = ../../secrets/secrets.yaml;
        defaultSopsFormat = "yaml";
        age.keyFile = "/var/lib/sops-nix/key.txt";

        secrets = {
          lldap-jwt-secret = {
            key = "lldap/jwt-secret";
            owner = "lldap";
            group = "lldap";
            mode = "0400";
            restartUnits = [ "lldap.service" ];
          };
          lldap-user-pass = {
            key = "lldap/user-pass";
            owner = "lldap";
            group = "lldap";
            mode = "0400";
            restartUnits = [ "lldap.service" ];
          };
        };
      };

      networking.firewall.allowedTCPPorts = [ 3890 3000 ];
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

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
        User = "lldap";
        Group = "lldap";
      };

      # Define user/group dynamically
      users.users.lldap = {
        isSystemUser = true;
        group = "lldap";
        description = "LLDAP service user";
      };
      users.groups.lldap = { };

      system.stateVersion = "26.05";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/lldap 0750 root root -"
  ];
}
