{ config, lib, inputs, ... }:
let
  hostConfig = config;
  cfg = hostConfig.hlamlab.services;
  enabledServices = lib.filterAttrs (n: v: v.enable) cfg;
  alloyConfig = import ../common/network/alloy-config.nix;

  # The host's end of every container's veth: the containers' gateway, and
  # where Traefik answers them.
  hostAddress = "10.0.0.1";

  # Every name Traefik publishes. Containers resolve these to the host, so a
  # service calling a sibling by its public URL (OIDC backchannel, WOPI) goes
  # through the local Traefik — same name, same certificate, never the tunnel.
  publicNames = lib.mapAttrsToList (n: svc: svc.fqdn)
    (lib.filterAttrs (n: svc: svc.traefik.enable) enabledServices);
in
{
  options.hlamlab.observability.enable = lib.mkEnableOption ''
    per-container observability: persistent journald, an Alloy agent shipping the
    container's own journal to Loki, and a node_exporter restricted to the
    collectors that are actually namespaced. nspawn surfaces neither the inner
    journals nor the inner systemd to the host, so both agents have to run inside
  '';

  options.hlamlab.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, config, ... }: {
      options = {
        enable = lib.mkEnableOption "Enable ${name} service";

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

        # Derived read-only handles. Reference these from sibling services
        # instead of hardcoding another service's prefix, IP, or port — change a
        # domainPrefix/ip/port once and every cross-reference follows.
        fqdn = lib.mkOption {
          type = lib.types.str;
          default = "${config.domainPrefix}.${hostConfig.hlamlab.settings.domain}";
          readOnly = true;
          description = "Fully-qualified public hostname (domainPrefix + settings.domain).";
        };

        baseUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://${config.fqdn}";
          readOnly = true;
          description = "Public HTTPS base URL (https://<fqdn>).";
        };

        address = lib.mkOption {
          type = lib.types.str;
          default = "${config.ip}:${toString config.port}";
          readOnly = true;
          description = "Internal container address (ip:port) for sibling services to reach directly over the private network.";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/${name}";
          description = ''
            Path inside the container that the service's ZFS-backed state
            directory is bind-mounted onto. Override only when the upstream
            NixOS module insists on another path (collabora wants /var/lib/cool).
          '';
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
          description = "Bind mounts in addition to the automatic dataDir and sops key mounts";
        };

        traefikMiddlewares = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "security-headers" ];
          description = "Traefik middlewares for the router";
        };

        serviceUser = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "The name of the service user to create, and to use as default owner for secrets and dataDir";
        };

        secrets = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              key = lib.mkOption { type = lib.types.str; };
              owner = lib.mkOption { type = lib.types.str; default = name; };
              restartUnits = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "${name}.service" ]; };
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

        nameservers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "1.1.1.1" "1.0.0.1" ];
          description = ''
            Resolvers for the container, used for internet egress only. Sibling
            services' public names never reach them: `networking.hosts` maps
            those to the host's Traefik.
          '';
        };

        traefik.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Publish this service through Traefik";
        };

        zfs.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Give this service its own ZFS dataset, bind mount and snapshot schedule";
        };

        containerConfig = lib.mkOption {
          type = lib.types.unspecified;
          description = "NixOS configuration for inside the container";
        };
      };
    }));
    default = { };
  };

  config = lib.mkIf (enabledServices != { }) {
    # 1. Container configurations
    containers = lib.mapAttrs
      (name: svc: {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress;
        localAddress = svc.ip;

        bindMounts = {
          "/var/lib/sops-nix/key.txt" = {
            hostPath = "/var/lib/sops-nix/key.txt";
            isReadOnly = true;
          };
        }
        // lib.optionalAttrs svc.zfs.enable {
          ${svc.dataDir} = {
            hostPath = "/var/lib/services/${name}";
            isReadOnly = false;
          };
        }
        // svc.bindMounts;

        config = { ... }: {
          imports = [
            inputs.sops-nix.nixosModules.sops
            svc.containerConfig
          ];

          config = lib.mkMerge [
            {
              sops = {
                defaultSopsFile = ../secrets/secrets.yaml;
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

              networking.nameservers = svc.nameservers;
              networking.hosts.${hostAddress} = publicNames;
              networking.firewall.allowedTCPPorts = [ svc.port ];
              system.stateVersion = hostConfig.system.stateVersion;

              users.users.${svc.serviceUser} = {
                isSystemUser = true;
                group = svc.serviceUser;
                description = lib.mkDefault "${name} service user";
              };
              users.groups.${svc.serviceUser} = { };
            }
            # The bind mount arrives owned by root:root from the host. Hand it to
            # the user that actually runs the service — upstream units that set
            # `StateDirectory=` would do this themselves, but the ones that run
            # under uwsgi or a DynamicUser emperor (searx) never do.
            (lib.optionalAttrs svc.zfs.enable {
              systemd.tmpfiles.rules = [
                "d ${svc.dataDir} 0750 ${svc.serviceUser} ${svc.serviceUser} -"
              ];
            })
            # Persistent journald so the log agent below has a stable journal to
            # read across container restarts.
            (lib.optionalAttrs hostConfig.hlamlab.observability.enable {
              services.journald.settings.Journal = {
                Storage = "persistent";
                SystemMaxUse = "100M";
              };

              # nspawn shares the host kernel and does NOT virtualise /proc, so
              # cpu/meminfo/loadavg/diskstats read host-global here — ten
              # containers would report ten identical copies. Those come from the
              # host's own node_exporter and from cAdvisor's cgroup view instead
              # (modules/common/network/exporters.nix).
              #
              # What IS per-container, and has no host-side substitute:
              #   systemd     - the container's own D-Bus. Unit state for
              #                 immich-server.service & co; neither the host's
              #                 systemd nor cAdvisor can see these at all.
              #   filesystem  - the container's mount namespace, i.e. the usage of
              #                 its bind-mounted ZFS dataset. cAdvisor reports no
              #                 filesystem stats for nspawn cgroups.
              #   netdev      - privateNetwork gives each container its own netns,
              #                 so /proc/net/dev is genuinely its own.
              # disable-defaults keeps it to exactly those three.
              services.prometheus.exporters.node = {
                enable = true;
                listenAddress = "0.0.0.0";
                # Not 9100: opencloud's microservices claim ports from 9100 up.
                port = 9101;
                openFirewall = true;
                enabledCollectors = [ "systemd" "filesystem" "netdev" ];
                extraFlags = [ "--collector.disable-defaults" ];
              };

              services.alloy.enable = true;
              systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "systemd-journal" ];
              # Labelled job=<container> so Grafana's Log Viewer lists each
              # service by name; narrow further with the `unit` filter.
              environment.etc."alloy/config.alloy".text = alloyConfig {
                lokiUrl = "http://${cfg.loki.address}/loki/api/v1/push";
                labels = ''job = "${name}", container = "${name}"'';
              };
            })
          ];
        };
      })
      enabledServices;

    # 2. DNS Mapping (Host -> Container)
    networking.hosts = lib.mapAttrs' (name: svc: lib.nameValuePair svc.ip [ name ]) enabledServices;

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
      (name: svc: lib.optionalAttrs svc.zfs.enable {
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
    systemd.services = lib.mapAttrs'
      (name: svc: lib.nameValuePair "container@${name}" {
        serviceConfig = {
          CPUQuota = svc.cpuLimit;
          MemoryMax = svc.ramLimit;
          MemoryHigh = svc.ramHigh;
          MemorySwapMax = "0B";
          TasksMax = 512;
        };
      })
      enabledServices;

    # 6. Traefik Routing
    services.traefik.dynamicConfigOptions.http = {
      routers = lib.mkMerge (lib.mapAttrsToList
        (name: svc: lib.optionalAttrs svc.traefik.enable {
          "${name}" = {
            rule = "Host(`${svc.fqdn}`)";
            service = name;
            entryPoints = [ "https" ];
            # No `tls` here: the https entrypoint carries it (traefik.nix), and
            # a router-level block would replace it wholesale.
            middlewares = svc.traefikMiddlewares;
          };
        })
        enabledServices);

      services = lib.mkMerge (lib.mapAttrsToList
        (name: svc: lib.optionalAttrs svc.traefik.enable {
          "${name}" = {
            loadBalancer = {
              servers = [{ url = "http://${svc.address}"; }];
              passHostHeader = true;
            };
          };
        })
        enabledServices);
    };

    # 7. Host state directories: the /var/lib/services root plus one 0750 dir
    # per service (the ZFS dataset mountpoint). Folded in here so service
    # modules don't each repeat their own tmpfiles rule.
    systemd.tmpfiles.rules = [
      "d /var/lib/services 0755 root root -"
    ] ++ lib.mapAttrsToList
      (name: svc: "d /var/lib/services/${name} 0750 - - -")
      (lib.filterAttrs (n: svc: svc.zfs.enable) enabledServices);
  };
}
