{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  # Native NixOS container running OpenCloud
  containers.opencloud = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1"; # host side of the veth
    localAddress = "10.0.0.2"; # container IP

    # Bind mount: Host storage → Container storage
    # This makes OpenCloud state persist across container recreation
    bindMounts = {
      "/var/lib/opencloud" = {
        hostPath = "/var/lib/services/opencloud";
        isReadOnly = false;
      };
    };

    config = { pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 9200 ];

      services.opencloud = {
        enable = true;
        package = pkgs.opencloud;
        url = "https://opencloud.${vars.domain}"; # Public URL for proper operation behind Traefik
        address = "0.0.0.0";
        port = 9200;
        # settings = { ... }; # optional extra YAML mapped to /etc/opencloud/*.yaml
      };

      system.stateVersion = "26.05";
    };
  };

  # Create the host directory for OpenCloud state storage
  # This directory will be bind-mounted into the container
  # Ownership will be managed by the container's opencloud user automatically
  systemd.tmpfiles.rules = [
    "d /var/lib/services 0755 root root -"
    "d /var/lib/services/opencloud 0755 root root -"
  ];
}

