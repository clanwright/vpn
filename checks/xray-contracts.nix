{
  inputs,
  pkgs,
  root,
  self,
  system,
}:
let
  lib = inputs.nixpkgs.lib;
  fixture = import ./fixtures/example-clan.nix;
  settings = fixture.instances.vpn-mihomo-vless-xhttp.roles.gateway.machines.vpn-fixture.settings;
  service = import ../clanServices/mihomo-vless-xhttp/default.nix {
    inherit lib;
    xrayPackageFor = targetSystem: self.packages.${targetSystem}.xray;
  };
  providerExport =
    (service.roles.gateway.perInstance {
      inherit settings;
      instanceName = "vpn-mihomo-vless-xhttp";
      machine.name = "vpn-fixture";
      mkExports = value: value;
    }).exports.vpnProvider;
  schemaResult =
    value:
    builtins.tryEval (
      builtins.deepSeq
        (lib.evalModules {
          modules = [
            (service.roles.gateway.interface { inherit lib; })
            { config = value; }
          ];
        }).config
        true
    );
  moduleForWithInstances =
    rawSettings: firewall: activeInstances:
    let
      secretNames = [
        rawSettings.reality.privateKeySecretName
      ]
      ++ map (profile: profile.vlessUuidSecretName) rawSettings.profiles;
      config = {
        clanwright.vpn.xrayVless = { inherit activeInstances; };
        networking.firewall = firewall;
        sops = {
          useSystemdActivation = true;
          placeholder = lib.genAttrs secretNames (name: "<SOPS:${name}:PLACEHOLDER>");
          templates."xray-vless-xhttp.json".path = "/run/secrets-rendered/xray-vless-xhttp.json";
        };
      };
      instance = service.roles.gateway.perInstance {
        settings = rawSettings;
        instanceName = "vpn-mihomo-vless-xhttp";
        machine.name = "vpn-fixture";
      };
    in
    instance.nixosModule { inherit config lib pkgs; };
  moduleFor =
    rawSettings: firewall: moduleForWithInstances rawSettings firewall [ "vpn-mihomo-vless-xhttp" ];
  nftablesFirewall = {
    enable = true;
    backend = "nftables";
  };
  assertionsPass =
    rawSettings: firewall:
    builtins.all (entry: entry.assertion) (moduleFor rawSettings firewall).assertions;
  unwrap =
    value:
    if builtins.isAttrs value && (value._type or null) == "if" then
      if value.condition then unwrap value.content else null
    else if builtins.isAttrs value && (value._type or null) == "order" then
      unwrap value.content
    else if builtins.isAttrs value && (value._type or null) == "override" then
      unwrap value.content
    else
      value;
  highPortSettings = settings // {
    port = 8443;
  };
  highPortModule = moduleFor highPortSettings nftablesFirewall;
  disabledModule = moduleForWithInstances (settings // { enable = false; }) nftablesFirewall [ ];
  highPortCapabilitiesContract =
    builtins.all (entry: entry.assertion) highPortModule.assertions
    && unwrap highPortModule.systemd.services.xray.serviceConfig.AmbientCapabilities == [ ]
    && unwrap highPortModule.systemd.services.xray.serviceConfig.CapabilityBoundingSet == [ ];
  secondProfile = {
    name = "second";
    kind = "mobile";
    publishProfileJson = false;
    vlessUuidSecretName = "fixture-vless-uuid-second";
    realityShortId = "fedcba9876543210";
  };
  negativeAssertionResults = {
    wildcardBind = !(assertionsPass (settings // { bindIPv4 = "0.0.0.0"; }) nftablesFirewall);
    duplicateProfileName =
      !(assertionsPass (
        settings
        // {
          profiles = settings.profiles ++ [
            (secondProfile // { inherit (builtins.head settings.profiles) name; })
          ];
        }
      ) nftablesFirewall);
    duplicateUuidSecret =
      !(assertionsPass (
        settings
        // {
          profiles = settings.profiles ++ [
            (
              secondProfile
              // {
                inherit (builtins.head settings.profiles) vlessUuidSecretName;
              }
            )
          ];
        }
      ) nftablesFirewall);
    duplicateShortId =
      !(assertionsPass (
        settings
        // {
          profiles = settings.profiles ++ [
            (
              secondProfile
              // {
                inherit (builtins.head settings.profiles) realityShortId;
              }
            )
          ];
        }
      ) nftablesFirewall);
    duplicateServerName =
      !(assertionsPass (
        settings
        // {
          reality = settings.reality // {
            serverNames = settings.reality.serverNames ++ [ (builtins.head settings.reality.serverNames) ];
          };
        }
      ) nftablesFirewall);
    duplicateServerNameCaseInsensitive =
      !(assertionsPass (
        settings
        // {
          reality = settings.reality // {
            serverNames = settings.reality.serverNames ++ [ "DONOR.EXAMPLE.INVALID" ];
          };
        }
      ) nftablesFirewall);
    privateKeyUuidCollision =
      !(assertionsPass (
        settings
        // {
          reality = settings.reality // {
            privateKeySecretName = (builtins.head settings.profiles).vlessUuidSecretName;
          };
        }
      ) nftablesFirewall);
    targetEqualsEndpoint =
      !(assertionsPass (
        settings
        // {
          reality = settings.reality // {
            targetHost = settings.domain;
            serverNames = [ settings.domain ];
          };
        }
      ) nftablesFirewall);
    targetEqualsEndpointCaseInsensitive =
      !(assertionsPass (
        settings
        // {
          reality = settings.reality // {
            targetHost = "VLESS.EXAMPLE.INVALID";
            serverNames = [ "VLESS.EXAMPLE.INVALID" ];
          };
        }
      ) nftablesFirewall);
    firewallDisabled = !(assertionsPass settings (nftablesFirewall // { enable = false; }));
    iptablesFirewall = !(assertionsPass settings (nftablesFirewall // { backend = "iptables"; }));
    duplicateActiveInstance =
      !(builtins.all (entry: entry.assertion)
        (moduleForWithInstances settings nftablesFirewall [
          "vpn-mihomo-vless-xhttp"
          "vpn-mihomo-vless-xhttp-second"
        ]).assertions
      );
  };
  negativeAssertionsContract = builtins.all (value: value) (
    builtins.attrValues negativeAssertionResults
  );
  consumer = (import ./lib/consumer.nix { inherit inputs root self; }) {
    instanceNames = [ "vpn-mihomo-vless-xhttp" ];
  };
  inherit (consumer) machine;
  template = machine.sops.templates."xray-vless-xhttp.json";
  rendered = builtins.fromJSON template.content;
  inbound = builtins.head rendered.inbounds;
  reality = inbound.streamSettings.realitySettings;
  xhttp = inbound.streamSettings.xhttpSettings;
  unit = machine.systemd.services.xray;
  inherit (unit) serviceConfig;
  malformedSchemasRejected = builtins.all (result: !result.success) [
    (schemaResult (settings // { bindIPv4 = "0.0.0.0/0"; }))
    (schemaResult (
      settings
      // {
        xhttp = settings.xhttp // {
          path = "missing-leading-slash";
        };
      }
    ))
    (schemaResult (
      settings
      // {
        profiles = map (profile: profile // { realityShortId = "not-hex"; }) settings.profiles;
      }
    ))
    (schemaResult (
      settings
      // {
        profiles = map (profile: profile // { realityShortId = "ABCDEF0123456789"; }) settings.profiles;
      }
    ))
    (schemaResult (
      settings
      // {
        profiles = map (profile: profile // { realityShortId = "aa"; }) settings.profiles;
      }
    ))
    (schemaResult (
      settings
      // {
        profiles = map (profile: profile // { realityShortId = "aa00"; }) settings.profiles;
      }
    ))
    (schemaResult (
      settings
      // {
        reality = settings.reality // {
          target = {
            host = settings.reality.targetHost;
          };
        };
      }
    ))
  ];
  exportContract =
    providerExport.protocol == "vless-xhttp"
    &&
      providerExport.endpoint == {
        inherit (settings) domain port;
        ipv4 = settings.bindIPv4;
        transport = "tcp";
      }
    && providerExport.profileNames == map (profile: profile.name) settings.profiles
    && providerExport.secretNames.realityPrivateKey == settings.reality.privateKeySecretName
    &&
      providerExport.secretNames.vlessUuid == lib.listToAttrs (
        map (profile: {
          inherit (profile) name;
          value = profile.vlessUuidSecretName;
        }) settings.profiles
      )
    &&
      providerExport.transportMetadata.reality == {
        serverName = settings.reality.targetHost;
        inherit (settings.reality) serverNames publicKey;
        target = "${settings.reality.targetHost}:443";
        shortIdsByProfile = lib.listToAttrs (
          map (profile: {
            inherit (profile) name;
            value = profile.realityShortId;
          }) settings.profiles
        );
      }
    &&
      providerExport.transportMetadata.xhttp == {
        inherit (settings.xhttp) path;
        mode = "auto";
      };
  templateContract =
    builtins.attrNames rendered == [
      "inbounds"
      "log"
      "outbounds"
    ]
    && rendered.log.loglevel == "warning"
    && builtins.length rendered.inbounds == 1
    && inbound.tag == "vless-xhttp-in"
    && inbound.listen == settings.bindIPv4
    && inbound.port == settings.port
    && inbound.protocol == "vless"
    && inbound.settings.decryption == "none"
    && !(inbound.settings ? fallbacks)
    && builtins.all (
      client:
      builtins.attrNames client == [
        "email"
        "id"
      ]
    ) inbound.settings.clients
    &&
      map (client: client.email) inbound.settings.clients == map (profile: profile.name) settings.profiles
    && !(inbound ? flow)
    && inbound.streamSettings.network == "xhttp"
    && inbound.streamSettings.security == "reality"
    && reality.show == false
    && reality.target == "${settings.reality.targetHost}:443"
    && reality.xver == 0
    && reality.serverNames == settings.reality.serverNames
    && reality.shortIds == map (profile: profile.realityShortId) settings.profiles
    && reality.privateKey == machine.sops.placeholder.${settings.reality.privateKeySecretName}
    &&
      map (client: client.id) inbound.settings.clients
      == map (profile: machine.sops.placeholder.${profile.vlessUuidSecretName}) settings.profiles
    &&
      builtins.attrNames reality == [
        "privateKey"
        "serverNames"
        "shortIds"
        "show"
        "target"
        "xver"
      ]
    &&
      xhttp == {
        inherit (settings.xhttp) path;
        mode = "auto";
      }
    && builtins.length rendered.outbounds == 1
    &&
      builtins.head rendered.outbounds == {
        protocol = "freedom";
        tag = "direct";
      };
  runtimeContract =
    builtins.all (entry: entry.assertion) machine.assertions
    && machine.services.xray.enable
    && machine.services.xray.package == self.packages.${system}.xray
    && machine.services.xray.settings == null
    && machine.services.xray.settingsFile == template.path
    && template.owner == "root"
    && template.group == "root"
    && template.mode == "0400"
    && template.restartUnits == [ "xray.service" ]
    && serviceConfig.LoadCredential == "config.json:${template.path}"
    && lib.hasInfix "$CREDENTIALS_DIRECTORY/config.json" unit.script
    && serviceConfig.DynamicUser == true
    && serviceConfig.AmbientCapabilities == [ "CAP_NET_BIND_SERVICE" ]
    && serviceConfig.CapabilityBoundingSet == [ "CAP_NET_BIND_SERVICE" ]
    && serviceConfig.NoNewPrivileges == true
    && serviceConfig.ProtectSystem == "strict"
    && serviceConfig.ProtectHome == true
    && serviceConfig.PrivateDevices == true
    && serviceConfig.PrivateTmp == true
    && !(builtins.elem "sops-install-secrets.service" (unit.requires or [ ]));
  exposureContract =
    machine.networking.firewall.enable
    && machine.networking.firewall.backend == "nftables"
    && !(builtins.elem settings.port machine.networking.firewall.allowedTCPPorts)
    && lib.hasInfix "ip daddr ${settings.bindIPv4} tcp dport ${toString settings.port} accept" machine.networking.firewall.extraInputRules;
  independentRuntime =
    machine.systemd.services ? xray
    && !(machine.systemd.services ? mihomo-gateway)
    && !((machine.networkCore or { }) ? mihomo);
  disabledContract =
    (disabledModule.services or { }) == { }
    && (disabledModule.systemd or { }) == { }
    && ((disabledModule.sops or { }).secrets or { }) == { }
    && ((disabledModule.sops or { }).templates or { }) == { };
  contract =
    malformedSchemasRejected
    && negativeAssertionsContract
    && exportContract
    && templateContract
    && runtimeContract
    && highPortCapabilitiesContract
    && exposureContract
    && independentRuntime
    && disabledContract;
in
if !contract then
  throw "Xray VLESS contract failed: ${
    builtins.toJSON {
      inherit
        exposureContract
        exportContract
        highPortCapabilitiesContract
        independentRuntime
        malformedSchemasRejected
        negativeAssertionResults
        negativeAssertionsContract
        runtimeContract
        templateContract
        ;
    }
  }"
else
  {
    all = true;
    inherit
      exposureContract
      exportContract
      highPortCapabilitiesContract
      independentRuntime
      malformedSchemasRejected
      negativeAssertionsContract
      runtimeContract
      templateContract
      ;
  }
