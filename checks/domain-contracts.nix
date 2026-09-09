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
  appsPkgs = import inputs.apps-nixpkgs { inherit system; };
  consume = import ./lib/consumer.nix { inherit inputs root self; };
  serviceSpecs = {
    vpn-mihomo-vless-xhttp.role = "gateway";
    vpn-mihomo-hysteria2.role = "gateway";
    vpn-amneziawg.role = "gateway";
    vpn-naiveproxy.role = "addon";
    vpn-client-profiles.role = "publisher";
    dns-adguardhome.role = "resolver";
    dns-unbound.role = "recursive-backend";
  };
  serviceNames = builtins.attrNames serviceSpecs;
  appsPkgsFor =
    targetSystem:
    import inputs.apps-nixpkgs { system = targetSystem; }
    // {
      inherit (self.packages.${targetSystem})
        amneziawg-go
        amneziawg-tools
        sing-box
        ;
    };
  services = {
    vpn-mihomo-vless-xhttp = import ../clanServices/mihomo-vless-xhttp/default.nix {
      inherit lib;
      mihomoPackageFor = targetSystem: self.packages.${targetSystem}.mihomo;
      xrayPackageFor = targetSystem: self.packages.${targetSystem}.xray;
    };
    vpn-mihomo-hysteria2 = import ../clanServices/mihomo-hysteria2/default.nix {
      inherit lib;
      mihomoPackageFor = targetSystem: self.packages.${targetSystem}.mihomo;
    };
    vpn-amneziawg = import ../clanServices/amneziawg/default.nix {
      inherit lib appsPkgsFor;
    };
    vpn-naiveproxy = import ../clanServices/naiveproxy/default.nix { inherit lib; };
    vpn-client-profiles = import ../clanServices/vpn-client-profiles/default.nix {
      inherit lib appsPkgsFor;
      clanLib = inputs.clan-core.lib;
      mihomoPackageFor = targetSystem: self.packages.${targetSystem}.mihomo;
    };
    dns-adguardhome = import ../clanServices/adguardhome/default.nix {
      adguardPackageFor = targetSystem: self.packages.${targetSystem}.adguardhome;
      dnsproxyPackageFor = targetSystem: self.packages.${targetSystem}.dnsproxy;
    };
    dns-unbound = import ../clanServices/unbound/default.nix {
      unboundPackageFor = targetSystem: self.packages.${targetSystem}.unbound;
    };
  };
  settingsFor = name: role: fixture.instances.${name}.roles.${role}.machines.vpn-fixture.settings;
  awgInstance = services.vpn-amneziawg.roles.gateway.perInstance {
    settings = settingsFor "vpn-amneziawg" "gateway";
    instanceName = "vpn-amneziawg";
    machine.name = "vpn-fixture";
    mkExports = value: value;
  };
  awgProvider = awgInstance.exports.vpnProvider;
  selectAwgProvider =
    raw:
    (self.lib.vpnExports { inherit lib; }).selectVpnProvider {
      providerInstanceId = "vpn-amneziawg";
      providerMachine = "vpn-fixture";
      providerRole = "gateway";
      protocol = "amneziawg";
      consumerInstanceId = "contract-check";
      selectExports = _predicate: exports: exports;
      exports.only.vpnProvider = raw;
    };
  awgTransportContract =
    builtins.deepSeq (selectAwgProvider awgProvider) true
    && !(builtins.tryEval (
      builtins.deepSeq (selectAwgProvider (
        lib.recursiveUpdate awgProvider { endpoint.transport = "tcp"; }
      )) true
    )).success;
  naiveSettings =
    (lib.evalModules {
      modules = [
        (services.vpn-naiveproxy.roles.addon.interface { inherit lib; })
        { config = settingsFor "vpn-naiveproxy" "addon"; }
      ];
    }).config;
  naiveInstance = services.vpn-naiveproxy.roles.addon.perInstance {
    settings = naiveSettings;
    instanceName = "vpn-naiveproxy";
    machine.name = "vpn-fixture";
    mkExports = value: value;
  };
  naiveProvider = naiveInstance.exports.vpnProvider;
  selectNaiveProvider =
    raw:
    (self.lib.vpnExports { inherit lib; }).selectVpnProvider {
      providerInstanceId = "vpn-naiveproxy";
      providerMachine = "vpn-fixture";
      providerRole = "addon";
      protocol = "naiveproxy";
      consumerInstanceId = "contract-check";
      selectExports = _predicate: exports: exports;
      exports.only.vpnProvider = raw;
    };
  naiveProviderResults = {
    actual = builtins.deepSeq (selectNaiveProvider naiveProvider) true;
    unknownProfileRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectNaiveProvider (
          naiveProvider
          // {
            profileNames = naiveProvider.profileNames ++ [ "unknown-profile" ];
          }
        )) true
      )).success;
    missingPasswordRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectNaiveProvider (
          naiveProvider
          // {
            secretNames = naiveProvider.secretNames // {
              password = builtins.removeAttrs naiveProvider.secretNames.password [ "probe" ];
            };
          }
        )) true
      )).success;
    extraPasswordRejected =
      !(builtins.tryEval (
        builtins.deepSeq (selectNaiveProvider (
          lib.recursiveUpdate naiveProvider {
            secretNames.password.unexpected = "fixture-unexpected-secret";
          }
        )) true
      )).success;
  };
  naiveProviderContract = builtins.all (value: value) (builtins.attrValues naiveProviderResults);
  schemaResult =
    name: value:
    let
      role = serviceSpecs.${name}.role;
      service = services.${name};
    in
    builtins.tryEval (
      builtins.deepSeq
        (lib.evalModules {
          modules = [
            (service.roles.${role}.interface { inherit lib; })
            { config = value; }
          ];
        }).config
        true
    );
  validSchemaResults = lib.genAttrs serviceNames (
    name:
    let
      role = serviceSpecs.${name}.role;
    in
    (schemaResult name (settingsFor name role)).success
  );
  validSchemas = builtins.all (value: value) (builtins.attrValues validSchemaResults);
  registeredSchemas = builtins.all (
    name:
    let
      evaluated =
        (inputs.clan-core.lib.evalService {
          modules = [ self.clan.modules."@clanwright/${name}" ];
          prefix = [ ];
        }).config;
    in
    builtins.deepSeq evaluated.result.api.schema true
  ) serviceNames;
  closedSchemas = builtins.all (
    name:
    let
      role = serviceSpecs.${name}.role;
    in
    !(schemaResult name ((settingsFor name role) // { unexpected = true; })).success
  ) serviceNames;
  invalidNestedFields =
    !(schemaResult "vpn-mihomo-vless-xhttp" (
      (settingsFor "vpn-mihomo-vless-xhttp" "gateway")
      // {
        reality = (settingsFor "vpn-mihomo-vless-xhttp" "gateway").reality // {
          privateKey = "must-not-cross-contract";
        };
      }
    )).success
    && !(schemaResult "dns-adguardhome" (
      (settingsFor "dns-adguardhome" "resolver")
      // {
        ui = (settingsFor "dns-adguardhome" "resolver").ui // {
          unexpected = 1;
        };
      }
    )).success;
  invalidFieldTypes = builtins.all (result: !result.success) [
    (schemaResult "vpn-mihomo-vless-xhttp" (
      (settingsFor "vpn-mihomo-vless-xhttp" "gateway") // { port = "443"; }
    ))
    (schemaResult "vpn-amneziawg" ((settingsFor "vpn-amneziawg" "gateway") // { peers = "fixture"; }))
    (schemaResult "dns-unbound" (
      (settingsFor "dns-unbound" "recursive-backend")
      // {
        listen = (settingsFor "dns-unbound" "recursive-backend").listen // {
          port = "5335";
        };
      }
    ))
  ];
  placementBehavior =
    name: machine:
    {
      vpn-mihomo-vless-xhttp =
        machine.services.xray.enable
        && machine.systemd.services ? xray
        && !((machine.networkCore.mihomo or { }) ? vlessXhttp);
      vpn-mihomo-hysteria2 =
        machine.systemd.services ? mihomo-hysteria2
        && machine.sops.templates ? "mihomo-hysteria2.json"
        && !((machine.networkCore.mihomo or { }) ? hysteria2);
      vpn-amneziawg =
        machine.systemd.services ? wireguard-awg-fixture
        && !(machine.networking.wireguard.interfaces ? awg-fixture);
      vpn-naiveproxy = machine.sops.templates ? "naiveproxy-fixture.caddy";
      vpn-client-profiles = !(machine.systemd.services ? mihomo-client-caddy-fixture);
      dns-adguardhome = machine.services.adguardhome.enable;
      dns-unbound = machine.services.unbound.enable;
    }
    .${name};
  independentPlacementResults = lib.genAttrs serviceNames (
    name:
    let
      consumer = consume { instanceNames = [ name ]; };
    in
    builtins.attrNames consumer.config.inventory.instances == lib.sort builtins.lessThan [
      "edge-wildcard-certificate"
      "network-caddy"
      "network-certificates"
      name
    ]
    && builtins.length (builtins.attrNames consumer.config._services.allServices) == 4
    && placementBehavior name consumer.machine
  );
  independentPlacements = builtins.all (value: value) (
    builtins.attrValues independentPlacementResults
  );
  combined = consume { instanceNames = serviceNames; };
  inherit (combined) machine;
  overrideAttempt = consume {
    instanceNames = serviceNames;
    extraModule = {
      services = {
        adguardhome.package = pkgs.hello;
        dnsproxy.package = pkgs.hello;
        unbound.package = pkgs.hello;
      };
    };
  };
  awgOverrideRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (consume {
          instanceNames = [ "vpn-amneziawg" ];
          extraModule.nixpkgs.overlays = [
            (_final: _prev: {
              amneziawg-go = pkgs.hello;
              amneziawg-tools = pkgs.hello;
            })
          ];
        }).machine.system.build.toplevel.drvPath
        true
    )).success;
  awgOverlays = builtins.filter (
    overlay:
    let
      result = overlay pkgs pkgs;
    in
    result ? amneziawg-go && result ? amneziawg-tools
  ) machine.nixpkgs.overlays;
  awgOverlay = builtins.head awgOverlays;
  packageAuthorityResults = {
    adguard = machine.services.adguardhome.package == self.packages.${system}.adguardhome;
    adguardPinned =
      self.packages.${system}.adguardhome == appsPkgs.adguardhome
      && self.packages.${system}.adguardhome.version == "0.107.78";
    dnsproxy = machine.services.dnsproxy.package == self.packages.${system}.dnsproxy;
    dnsproxyUpstream = self.packages.${system}.dnsproxy == appsPkgs.dnsproxy;
    unbound = machine.services.unbound.package == self.packages.${system}.unbound;
    unboundUpstream =
      self.packages.${system}.unbound == appsPkgs.unbound-with-systemd
      && self.packages.${system}.unbound.version == "1.26.0";
    awgOverlayPresent = awgOverlays != [ ];
    awgGo = (awgOverlay pkgs pkgs).amneziawg-go == self.packages.${system}.amneziawg-go;
    awgTools = (awgOverlay pkgs pkgs).amneziawg-tools == self.packages.${system}.amneziawg-tools;
    awgFamily = (self.lib.awgValidation { inherit lib; }).packageFamiliesValid {
      inherit (self.packages.${system}) amneziawg-go amneziawg-tools;
    };
    adguardOverride =
      overrideAttempt.machine.services.adguardhome.package == self.packages.${system}.adguardhome;
    dnsproxyOverride =
      overrideAttempt.machine.services.dnsproxy.package == self.packages.${system}.dnsproxy;
    unboundOverride =
      overrideAttempt.machine.services.unbound.package == self.packages.${system}.unbound;
    inherit awgOverrideRejected;
  };
  packageAuthority = builtins.all (value: value) (builtins.attrValues packageAuthorityResults);
  dnsStateResults = {
    immutable = !machine.services.adguardhome.mutableSettings;
    adguardState = builtins.elem "AdGuardHome" (
      lib.toList machine.systemd.services.adguardhome.serviceConfig.StateDirectory
    );
    unboundState = builtins.elem "unbound" (
      lib.toList machine.systemd.services.unbound.serviceConfig.StateDirectory
    );
  };
  dnsStatePreserved = builtins.all (value: value) (builtins.attrValues dnsStateResults);
  contract =
    builtins.attrNames self.clan.modules == map (name: "@clanwright/${name}") serviceNames
    && validSchemas
    && registeredSchemas
    && closedSchemas
    && invalidNestedFields
    && invalidFieldTypes
    && independentPlacements
    && awgTransportContract
    && naiveProviderContract
    && packageAuthority
    && dnsStatePreserved;
in
if !contract then
  throw "VPN domain contract failed: ${
    builtins.toJSON {
      inherit
        closedSchemas
        awgTransportContract
        naiveProviderContract
        naiveProviderResults
        awgOverrideRejected
        dnsStatePreserved
        dnsStateResults
        independentPlacementResults
        independentPlacements
        invalidFieldTypes
        invalidNestedFields
        packageAuthority
        packageAuthorityResults
        registeredSchemas
        validSchemaResults
        validSchemas
        ;
    }
  }"
else
  {
    all = true;
    inherit
      closedSchemas
      awgTransportContract
      naiveProviderContract
      naiveProviderResults
      dnsStatePreserved
      independentPlacements
      invalidFieldTypes
      invalidNestedFields
      packageAuthority
      registeredSchemas
      validSchemas
      ;
  }
