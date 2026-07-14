{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.hlamlab.services;
  vars = import ./settings.nix;

  # Only filter services assigned to this host
  enabledServices = lib.filterAttrs (n: v: v.enable && v.host == config.networking.hostName) cfg;
in
{
  options.hlamlab.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, config, ... }: {
      options = {
        enable = lib.mkEnableOption "Enable ${name} service";

        host = lib.mkOption {
          type = lib.types.str;
          description = "Which physical NixOS host runs this container";
          default = "playground";
        };

        ip = lib.mkOption {
          type = lib.types.str;
          description = "Container local IP address (e.g. 10.0.0.5)";
        };

        port = lib.mkOption {
          type = lib.types.int;
          description = "Container service port exposed to Traefik";
        };

        domainPrefix = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Prefix for the domain, e.g. 'auth' for auth.domain.tld";
        };

        storageQuota = lib.mkOption {
          type = lib.types.str;
          default = "10G";
          description = "ZFS dataset quota";
        };

        storageReservation = lib.mkOption {
          type = lib.types.str;
          default = "1G";
          description = "ZFS dataset reservation";
        };

        bindMounts = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Additional bind mounts for the container";
        };

        traefikMiddlewares = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "security-headers" ];
          description = "Traefik middlewares for the router";
        };

        createServiceUser = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Automatically create a system user and group for this service";
        };

        serviceUser = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "The name of the service user to create, and to use as default owner for secrets";
        };

        secrets = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              key = lib.mkOption { type = lib.types.str; };
              owner = lib.mkOption { type = lib.types.str; default = name; };
              restartUnits = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
            };
          });
          default = { };
          description = "Simplified sops.secrets configuration";
        };

        ramLimit = lib.mkOption {
          type = lib.types.str;
          default = "1G";
          description = "Maximum RAM limit (MemoryMax) for the container";
        };

        ramHigh = lib.mkOption {
          type = lib.types.str;
          default = "512M";
          description = "Soft RAM limit (MemoryHigh) for the container";
        };

        cpuLimit = lib.mkOption {
          type = lib.types.str;
          default = "100%";
          description = "CPU limit (CPUQuota) for the container";
        };

        traefik = {
          enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable Traefik routing"; };
          rule = lib.mkOption {
            type = lib.types.str;
            default = "Host(`${config.domainPrefix}.${vars.domain}`)";
            description = "Traefik router rule";
          };
        };

        zfs = {
          enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable ZFS dataset creation"; };
        };

        sanoid = {
          enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable Sanoid snapshots"; };
        };

        extraContainerConfig = lib.mkOption {
          type = lib.types.deferredModule;
          default = { };
          description = "Arbitrary NixOS configuration injected into the container";
        };

        containerConfig = lib.mkOption {
          type = lib.types.unspecified;
          description = "NixOS configuration for inside the container";
        };
      };
    }));
    default = { };
  };

  config = lib.mkIf (enabledServices != { }) (lib.mkMerge ([
    {
      # 1. Container configurations
      containers = lib.mapAttrs
        (name: svc: {
          autoStart = true;
          privateNetwork = true;
          hostAddress = "10.0.0.1";
          localAddress = svc.ip;

          bindMounts = {
            "/var/lib/sops-nix/key.txt" = {
              hostPath = "/var/lib/sops-nix/key.txt";
              isReadOnly = true;
            };
          } // svc.bindMounts;

          config = { config, pkgs, lib, ... }: lib.mkMerge [
            {
              imports = [ inputs.sops-nix.nixosModules.sops ];

              sops = {
                defaultSopsFile = ../../secrets/secrets.yaml;
                defaultSopsFormat = "yaml";
                age.keyFile = "/var/lib/sops-nix/key.txt";
                secrets = lib.mapAttrs
                  (sname: sval: {
                    key = sval.key;
                    owner = if sval.owner == name then svc.serviceUser else sval.owner;
                    group = if sval.owner == name then svc.serviceUser else sval.owner;
                    mode = "0400";
                    restartUnits = sval.restartUnits;
                  })
                  svc.secrets;
              };

              networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];
              networking.firewall.allowedTCPPorts = [ svc.port ];
              system.stateVersion = "26.05";
            }
            (lib.optionalAttrs svc.createServiceUser {
              users.users.${svc.serviceUser} = {
                isSystemUser = true;
                group = svc.serviceUser;
                description = "${name} service user";
              };
              users.groups.${svc.serviceUser} = { };
            })
            (if builtins.isFunction svc.containerConfig then svc.containerConfig { inherit config pkgs lib; } else svc.containerConfig)
            svc.extraContainerConfig
          ];
        })
        enabledServices;

      # 2. DNS Mapping (Host -> Container)
      networking.hosts = lib.mkMerge (lib.mapAttrsToList
        (name: svc: {
          "${svc.ip}" = [ name ];
        })
        enabledServices);

      # 3. ZFS Datasets
      disko.devices.zpool.tank.datasets = lib.mkMerge (lib.mapAttrsToList
        (name: svc: lib.optionalAttrs svc.zfs.enable {
          "services/${name}" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/var/lib/services/${name}";
              quota = svc.storageQuota;
              reservation = svc.storageReservation;
              compression = "lz4";
              atime = "off";
            };
          };
        })
        enabledServices);

      # 4. Sanoid Snapshots
      services.sanoid.datasets = lib.mkMerge (lib.mapAttrsToList
        (name: svc: lib.optionalAttrs svc.sanoid.enable {
          "tank/services/${name}" = {
            hourly = 24;
            daily = 7;
            weekly = 4;
            monthly = 12;
            autosnap = true;
            autoprune = true;
          };
        })
        enabledServices);

      # 5. Resource Limits
      systemd.services = lib.mkMerge (lib.mapAttrsToList
        (name: svc: {
          "container@${name}" = {
            serviceConfig = {
              CPUQuota = svc.cpuLimit;
              CPUWeight = 100;
              MemoryMax = svc.ramLimit;
              MemoryHigh = svc.ramHigh;
              MemorySwapMax = "0B";
              IOWeight = 100;
              TasksMax = 512;
            };
          };
        })
        enabledServices);

      # 6. Traefik Routing
      services.traefik.dynamicConfigOptions.http = {
        routers = lib.mkMerge (lib.mapAttrsToList
          (name: svc: lib.optionalAttrs svc.traefik.enable {
            "${name}" = {
              rule = svc.traefik.rule;
              service = name;
              entryPoints = [ "https" ];
              tls = { };
              middlewares = svc.traefikMiddlewares;
            };
          })
          enabledServices);

        services = lib.mkMerge (lib.mapAttrsToList
          (name: svc: lib.optionalAttrs svc.traefik.enable {
            "${name}" = {
              loadBalancer = {
                servers = [{ url = "http://${name}:${toString svc.port}"; }];
                passHostHeader = true;
              };
            };
          })
          enabledServices);
      };

      # 7. Create root services directory if not exists
      systemd.tmpfiles.rules = [
        "d /var/lib/services 0755 root root -"
      ];
    }
  ]));
}
