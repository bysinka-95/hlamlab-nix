{ config, lib, ... }:
let
  svc = config.hlamlab.services;
in
{
  # Push notifications for this host (Grafana and Gatus alerts), received by
  # the Gotify Android app. Apps and clients authenticate with Gotify's own
  # tokens, so there is no Authelia gate in front. The web UI signs in through
  # Authelia (OIDC); the local admin stays as break-glass.
  hlamlab.services.gotify = {
    ip = "10.0.0.13";
    port = 8080;
    domainPrefix = "gotify";

    storageQuota = "1G";
    storageReservation = "100M";
    ramLimit = "256M";
    ramHigh = "192M";

    dataDir = "/var/lib/gotify-server";

    secrets = {
      gotify-oidc-secret = {
        key = "gotify/oidc-client-secret";
        unit = "gotify-server.service";
      };
      gotify-admin-password = {
        key = "gotify/admin-password";
        unit = "gotify-server.service";
      };
    };

    containerConfig = { ... }: {
      services.gotify = {
        enable = true;
        environment = {
          GOTIFY_SERVER_PORT = svc.gotify.port;
          # Traefik on the host: the client IP comes from its X-Forwarded-For.
          GOTIFY_SERVER_TRUSTEDPROXIES = "10.0.0.1";

          # Created only on the first start, with an empty database.
          GOTIFY_DEFAULTUSER_NAME = "admin";
          GOTIFY_DEFAULTUSER_PASS_FILE = svc.gotify.secrets.gotify-admin-password.path;

          GOTIFY_OIDC_ENABLED = "true";
          GOTIFY_OIDC_ISSUER = svc.authelia.baseUrl;
          GOTIFY_OIDC_CLIENTID = "gotify";
          GOTIFY_OIDC_CLIENTSECRET_FILE = svc.gotify.secrets.gotify-oidc-secret.path;
          GOTIFY_OIDC_REDIRECTURL = "${svc.gotify.baseUrl}/auth/oidc/callback";
          GOTIFY_OIDC_SCOPES = "openid,profile,email,groups";
          GOTIFY_OIDC_GROUPS_CLAIM = "groups";
          # `admins` is declared in lldap.nix.
          GOTIFY_OIDC_GROUPS_ADMIN = "admins";
          GOTIFY_OIDC_IDP_NAME = "Authelia";
          # Empty: use the Authelia session like the other services (the
          # default "login" asks for the password at each sign-in).
          GOTIFY_OIDC_PROMPT = "";
        };
      };

      # A fixed user, so the ZFS dataset on dataDir has a stable owner.
      systemd.services.gotify-server.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = svc.gotify.serviceUser;
        Group = svc.gotify.serviceUser;
        # The module default is 0755. The database holds the app tokens.
        StateDirectoryMode = "0750";
      };
    };
  };
}
