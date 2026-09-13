{ ... }:
{

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # mDNS, so deploy-rs can reach the host as `playground.local`.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  imports = [
    ./traefik.nix
    ./cloudflared.nix
    ./alloy.nix
    ./exporters.nix
  ];
}
