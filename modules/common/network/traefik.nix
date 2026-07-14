{ config, ... }:
let
  vars = import ../settings.nix;
in
{
  services.traefik = {
    enable = true;

    # Let NixOS handle directory creation
    dataDir = "/var/lib/traefik";

    # Static Configuration
    staticConfigOptions = {
      global = {
        checkNewVersion = true;
        sendAnonymousUsage = false;
      };

      # API and Dashboard
      api = {
        dashboard = true;
        insecure = false; # Secured via middleware in dynamic config
      };

      # Logging
      log = {
        level = "INFO";
        filePath = "/var/log/traefik/traefik.log";
      };

      accessLog = {
        filePath = "/var/log/traefik/access.log";
        format = "json";
        filters = {
          statusCodes = [ "200-299" "400-599" ];
        };
        bufferingSize = 0;
        fields = {
          headers = {
            defaultMode = "drop";
            names = {
              User-Agent = "keep";
            };
          };
        };
      };

      # Allow insecure backend connections (for internal services)
      serversTransport = {
        insecureSkipVerify = true;
      };

      # Entry Points
      entryPoints = {
        http = {
          address = ":80";
          http = {
            redirections = {
              entryPoint = {
                to = "https";
                scheme = "https";
              };
            };
          };
          forwardedHeaders = {
            trustedIPs = [ "127.0.0.1/8" "::1/128" "10.0.0.0/24" ];
          };
        };

        https = {
          address = ":443";
          forwardedHeaders = {
            trustedIPs = [ "127.0.0.1/8" "::1/128" "10.0.0.0/24" ];
          };
          http = {
            tls = {
              # Cloudflare mTLS will be configured in dynamic config
              options = "requireCloudflareMTLS";
            };
          };
        };
      };

      # Providers
      providers = {
        providersThrottleDuration = "2s";
      };
    };

    # Dynamic Configuration (native Nix instead of YAML files)
    dynamicConfigOptions = {
      http = {
        middlewares = {
          # Security headers middleware (shared by all services)
          security-headers = {
            headers = {
              frameDeny = true;
              sslRedirect = true;
              browserXssFilter = true;
              contentTypeNosniff = true;
              forceSTSHeader = true;
              stsIncludeSubdomains = true;
              stsPreload = true;
              stsSeconds = 31536000;
              customFrameOptionsValue = "SAMEORIGIN";
            };
          };

          # Rate limiting middleware
          rate-limit = {
            rateLimit = {
              average = 100;
              burst = 50;
              period = "1m";
            };
          };

          # Dashboard authentication
          dashboard-auth = {
            basicAuth = {
              users = [
                "traefik-cloudflared:$2y$05$cnSA/wrglqU0NQ3zB/6.duq7K.E6.E9KEXIHLQuH0vLFzD6K.KhbG"
              ];
              realm = "Traefik Dashboard";
            };
          };
        };

        routers = {
          # Traefik dashboard router
          dashboard = {
            rule = "Host(`traefik.${vars.domain}`)";
            service = "api@internal";
            entryPoints = [ "https" ];
            tls = { };
            middlewares = [ "dashboard-auth" "security-headers" ];
          };
        };
      };

      # TLS configuration for Cloudflare mTLS
      tls = {
        # Certificate stores - default certificate for HTTPS
        stores = {
          default = {
            defaultCertificate = {
              certFile = "/var/lib/traefik/certs/origin.crt";
              keyFile = "/var/lib/traefik/certs/origin.key";
            };
          };
        };

        # Certificates - make the origin cert available
        certificates = [
          {
            certFile = "/var/lib/traefik/certs/origin.crt";
            keyFile = "/var/lib/traefik/certs/origin.key";
          }
        ];

        # TLS options for Cloudflare mTLS
        options = {
          requireCloudflareMTLS = {
            sniStrict = true;
            minVersion = "VersionTLS12";
            clientAuth = {
              # Cloudflare's Authenticated Origin Pull CA (to verify Cloudflare)
              caFiles = [ "/var/lib/cloudflared/origin-ca.pem" ];
              clientAuthType = "RequireAndVerifyClientCert";
            };
          };
        };
      };
    };
  };

  # Use proper systemd service configuration for directories
  systemd.services.traefik = {
    serviceConfig = {
      # This creates:
      # - /var/log/traefik (for logs)
      # - /var/lib/traefik/certs (for certificates)
      # Both with proper permissions automatically
      LogsDirectory = "traefik";
      StateDirectory = "traefik/certs";
    };
  };

  # Open firewall ports for Traefik
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
