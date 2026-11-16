{ config, ... }:
let
  lan = config.hlamlab.settings.lanInterface;
in
{
  # SSH and mDNS answer on the LAN only — not to containers.
  networking.firewall.interfaces.${lan} = {
    allowedTCPPorts = config.services.openssh.ports;
    allowedUDPPorts = [ 5353 ];
  };

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # mDNS, so deploy-rs can reach the host as `playground.local`.
  services.avahi = {
    enable = true;
    openFirewall = false;
    nssmdns4 = true;
    settings.publish = {
      disable-publishing = false;
      publish-addresses = true;
    };
  };

  imports = [
    ./traefik.nix
    ./cloudflared.nix
    ./alloy.nix
    ./exporters.nix
    ./crowdsec.nix
  ];
}
