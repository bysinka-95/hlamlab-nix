{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  # Native NixOS container running Collabora Online
  containers.collabora = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.4";

    # Bind mount: Host storage -> Container storage
    bindMounts = {
      "/var/lib/coolwsd" = {
        hostPath = "/var/lib/services/collabora";
        isReadOnly = false;
      };
    };

    config = { ... }: {
      networking.firewall.allowedTCPPorts = [ 9980 ];

      # Allow container to query real Cloudflare DNS instead of relying on
      # host's unreachable systemd-resolved (127.0.0.53) for external routing
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

      services.collabora-online = {
        enable = true;
        port = 9980;

        # TLS is terminated by Traefik; keep HTTPS externally.
        settings = {
          ssl = {
            enable = false;
            termination = true;
          };

          storage.wopi = {
            "@allow" = true;
            host = [ "opencloud.${vars.domain}" ];
          };

          server_name = "collabora.${vars.domain}";
        };
      };

      system.stateVersion = "26.05";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services 0755 root root -"
    "d /var/lib/services/collabora 0755 root root -"
  ];
}
