{
  unboundPackageFor ? (_system: throw "unbound requires an explicit unboundPackageFor dependency"),
}:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/dns-unbound";
    description = "Local recursive DNS backend for AdGuard";
    readme = builtins.readFile ./README.md;
  };

  roles.recursive-backend = {
    description = "Local recursive DNS backend";
    interface =
      { lib, ... }:
      let
        validIPv4Octet =
          value: builtins.match "(0|[1-9][0-9]{0,2})" value != null && lib.toInt value <= 255;
        validLoopbackLiteral =
          host:
          if host == "::1" then
            true
          else
            let
              octets = lib.splitString "." host;
            in
            builtins.length octets == 4 && builtins.head octets == "127" && builtins.all validIPv4Octet octets;
        explicitListenHostsType = lib.types.addCheck (lib.types.listOf lib.types.str) (
          hosts: hosts != [ ] && builtins.all validLoopbackLiteral hosts
        );
      in
      {
        options = {
          listen.hosts = lib.mkOption {
            type = lib.types.nullOr explicitListenHostsType;
            default = null;
            description = ''
              Explicit nonempty loopback IP literals. Null selects 127.0.0.1 and
              also ::1 when IPv6 is enabled by the host.
            '';
          };
          listen.port = lib.mkOption {
            type = lib.types.ints.between 1 65535;
            default = 5335;
          };
          privacy = {
            prefetch = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            hideIdentity = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            hideVersion = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            qnameMinimisation = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
          };
          adguardIntegrationProvider = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum [ "dns-adguardhome" ]);
            default = "dns-adguardhome";
            description = ''
              Optional explicit AdGuard role integrated with this recursive backend.
              Null keeps Unbound independently selectable without an AdGuard startup edge.
            '';
          };
        };
      };

    perInstance =
      { settings, ... }:
      {
        nixosModule =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            unboundPackage = unboundPackageFor pkgs.system;
            explicitListenHosts = settings.listen.hosts;
            effectiveListenHosts =
              if explicitListenHosts == null then
                [ "127.0.0.1" ] ++ lib.optional config.networking.enableIPv6 "::1"
              else
                explicitListenHosts;
            hasIPv4Listener = builtins.any (host: host != "::1") effectiveListenHosts;
            hasIPv6Listener = builtins.elem "::1" effectiveListenHosts;
            effectiveAccessControl =
              lib.optional hasIPv4Listener "127.0.0.0/8 allow" ++ lib.optional hasIPv6Listener "::1/128 allow";
            effectiveSettings = config.services.unbound.settings;
            effectiveServer = config.services.unbound.settings.server;
            # Review new native defaults explicitly when advancing the platform
            # pin; freeform Unbound directives are not a public extension API.
            allowedServerKeys = [
              "access-control"
              "auto-trust-anchor-file"
              "cache-min-ttl"
              "chroot"
              "define-tag"
              "directory"
              "do-daemonize"
              "do-ip4"
              "do-ip6"
              "do-tcp"
              "do-udp"
              "domain-insecure"
              "edns-buffer-size"
              "harden-dnssec-stripped"
              "hide-identity"
              "hide-version"
              "interface"
              "interface-automatic"
              "ip-freebind"
              "module-config"
              "pidfile"
              "port"
              "prefetch"
              "qname-minimisation"
              "qname-minimisation-strict"
              "serve-expired"
              "serve-expired-client-timeout"
              "serve-expired-reply-ttl"
              "serve-expired-ttl"
              "serve-expired-ttl-reset"
              "tls-cert-bundle"
              "trust-anchor"
              "trust-anchor-file"
              "trusted-keys-file"
              "username"
              "val-permissive-mode"
            ];
          in
          {
            assertions = [
              {
                assertion = config.services.unbound.package == unboundPackage;
                message = "unbound: the runtime package must come from the VPN domain platform pin.";
              }
              {
                assertion =
                  explicitListenHosts == null
                  || config.networking.enableIPv6
                  || !(builtins.elem "::1" explicitListenHosts);
                message = "unbound: listen.hosts explicitly enables ::1 while host IPv6 is disabled.";
              }
              {
                assertion =
                  effectiveServer.interface == effectiveListenHosts
                  && effectiveServer.interface != [ ]
                  && !effectiveServer.interface-automatic
                  && builtins.all (
                    host: builtins.elem host [ "::1" ] || lib.hasPrefix "127." host
                  ) effectiveServer.interface;
                message = "unbound: effective interfaces must remain the configured nonempty loopback listener set.";
              }
              {
                assertion =
                  !(effectiveSettings ? include)
                  && !(effectiveSettings ? include-toplevel)
                  && !(effectiveServer ? include)
                  && config.services.unbound.checkconf;
                message = "unbound: include directives cannot bypass the effective loopback and DNSSEC policy.";
              }
              {
                assertion =
                  builtins.attrNames effectiveSettings == [
                    "remote-control"
                    "server"
                  ]
                  && builtins.attrNames effectiveServer == allowedServerKeys
                  &&
                    builtins.attrNames effectiveSettings.remote-control == [
                      "control-cert-file"
                      "control-enable"
                      "control-interface"
                      "control-key-file"
                      "server-cert-file"
                      "server-key-file"
                    ]
                  && !effectiveSettings.remote-control.control-enable;
                message = "unbound: freeform directives and remote control cannot replace the closed recursive backend policy.";
              }
              {
                assertion =
                  effectiveServer.port == settings.listen.port
                  && effectiveServer.port >= 1
                  && effectiveServer.port <= 65535;
                message = "unbound: the effective listener port must remain within 1-65535.";
              }
              {
                assertion = effectiveServer.access-control == effectiveAccessControl;
                message = "unbound: effective access control must allow only enabled loopback address families.";
              }
              {
                assertion =
                  config.services.unbound.enableRootTrustAnchor
                  && effectiveServer.auto-trust-anchor-file == "${config.services.unbound.stateDir}/root.key"
                  && effectiveServer.module-config == ''"validator iterator"''
                  && !effectiveServer.val-permissive-mode
                  && effectiveServer.harden-dnssec-stripped
                  && effectiveServer.domain-insecure == [ ]
                  && effectiveServer.trust-anchor == [ ]
                  && effectiveServer.trust-anchor-file == [ ]
                  && effectiveServer.trusted-keys-file == [ ];
                message = "unbound: effective DNSSEC validation and the native managed root trust anchor must remain enabled.";
              }
              {
                assertion =
                  effectiveServer.do-ip4
                  && effectiveServer.do-ip6 == config.networking.enableIPv6
                  && effectiveServer.do-udp
                  && effectiveServer.do-tcp
                  && effectiveServer.edns-buffer-size == 1232
                  && effectiveServer.cache-min-ttl == 0
                  && effectiveServer.serve-expired
                  && effectiveServer.serve-expired-ttl == 86400
                  && !effectiveServer.serve-expired-ttl-reset
                  && effectiveServer.serve-expired-client-timeout == 1800
                  && effectiveServer.serve-expired-reply-ttl == 30;
                message = "unbound: effective transport, EDNS, TTL, and bounded serve-expired policy must remain enabled.";
              }
              {
                assertion =
                  effectiveServer.prefetch == settings.privacy.prefetch
                  && effectiveServer.hide-identity == settings.privacy.hideIdentity
                  && effectiveServer.hide-version == settings.privacy.hideVersion
                  && effectiveServer.qname-minimisation == settings.privacy.qnameMinimisation
                  && !effectiveServer.qname-minimisation-strict;
                message = "unbound: effective privacy settings must retain non-strict QNAME minimisation.";
              }
            ];

            services.unbound = {
              enable = true;
              package = lib.mkForce unboundPackage;
              checkconf = lib.mkForce true;
              resolveLocalQueries = false;
              enableRootTrustAnchor = lib.mkForce true;
              settings.server = {
                port = lib.mkForce settings.listen.port;
                interface = lib.mkForce effectiveListenHosts;
                interface-automatic = lib.mkForce false;
                access-control = lib.mkForce effectiveAccessControl;
                do-ip4 = lib.mkForce true;
                do-ip6 = lib.mkForce config.networking.enableIPv6;
                do-udp = lib.mkForce true;
                do-tcp = lib.mkForce true;
                edns-buffer-size = lib.mkForce 1232;
                prefetch = lib.mkForce settings.privacy.prefetch;
                hide-identity = lib.mkForce settings.privacy.hideIdentity;
                hide-version = lib.mkForce settings.privacy.hideVersion;
                qname-minimisation = lib.mkForce settings.privacy.qnameMinimisation;
                qname-minimisation-strict = lib.mkForce false;
                module-config = lib.mkForce ''"validator iterator"'';
                val-permissive-mode = lib.mkForce false;
                harden-dnssec-stripped = lib.mkForce true;
                domain-insecure = lib.mkForce [ ];
                trust-anchor = lib.mkForce [ ];
                trust-anchor-file = lib.mkForce [ ];
                trusted-keys-file = lib.mkForce [ ];
                cache-min-ttl = lib.mkForce 0;
                serve-expired = lib.mkForce true;
                serve-expired-ttl = lib.mkForce 86400;
                serve-expired-ttl-reset = lib.mkForce false;
                serve-expired-client-timeout = lib.mkForce 1800;
                serve-expired-reply-ttl = lib.mkForce 30;
              };
            };
          }
          // lib.optionalAttrs (settings.adguardIntegrationProvider != null) {
            systemd.services.adguardhome.wants = [ "unbound.service" ];
          };
      };
  };
}
