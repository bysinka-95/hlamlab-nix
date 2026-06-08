# Local Configuration
#
# This file contains domain and tunnel ID configuration.
# Edit these values for your setup when forking this repository.
#
# These are dummy placeholder values - replace with your actual values:
# - domain: Your actual domain name (e.g., "yourdomain.com")
# - tunnelId: Your Cloudflare Tunnel ID from dashboard

let
  domain = "yourdomain.com";
  tunnelId = "00000000-0000-0000-0000-000000000000f";
  hostId = "1a23bc45"; # ZFS host ID

  # Helper to convert domain to LDAP base DN (e.g., "hlamlab.xyz" -> "dc=hlamlab,dc=xyz")
  # We use builtins.split and map to construct this.
  parts = builtins.filter (x: builtins.typeOf x == "string" && x != "") (builtins.split "\\." domain);
  ldapBaseDn = builtins.concatStringsSep "," (map (p: "dc=${p}") parts);
in
{
  inherit domain tunnelId hostId ldapBaseDn;
}
