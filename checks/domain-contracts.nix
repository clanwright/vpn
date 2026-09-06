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
    };
    dns-unbound = import ../clanServices/unbound/default.nix {
      unboundPackageFor = targetSystem: self.packages.${targetSystem}.unbound;
    };
  };
  settingsFor = name: role: fixture.instances.${name}.roles.${role}.machines.vpn-fixture.settings;
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
        builtins.length machine.networkCore.mihomo.vlessXhttp == 1
        && machine.systemd.services ? mihomo-gateway;
      vpn-mihomo-hysteria2 =
        builtins.length machine.networkCore.mihomo.hysteria2 == 1
        && machine.systemd.services ? mihomo-gateway;
      vpn-amneziawg = machine.networking.wireguard.interfaces ? awg-fixture;
      vpn-naiveproxy = machine.systemd.services ? naiveproxy-caddy-fragment-fixture;
      vpn-client-profiles = !(machine.systemd.services ? mihomo-client-caddy-fixture);
      dns-adguardhome = machine.services.adguardhome.enable;
      dns-unbound = machine.services.unbound.enable;
    }
    .${name};
  independentPlacements = builtins.all (
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
  ) serviceNames;
  combined = consume { instanceNames = serviceNames; };
  inherit (combined) machine;
  overrideAttempt = consume {
    instanceNames = serviceNames;
    extraModule = {
      services.adguardhome.package = pkgs.hello;
      services.unbound.package = pkgs.hello;
      networkCore.mihomo.packages = [ pkgs.hello ];
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
    adguardUpstream =
      self.packages.${system}.adguardhome == inputs.nixpkgs.legacyPackages.${system}.adguardhome;
    unbound = machine.services.unbound.package == self.packages.${system}.unbound;
    unboundUpstream =
      self.packages.${system}.unbound == inputs.nixpkgs.legacyPackages.${system}.unbound;
    mihomo = machine.networkCore.mihomo.packages == [ self.packages.${system}.mihomo ];
    awgOverlayPresent = awgOverlays != [ ];
    awgGo = (awgOverlay pkgs pkgs).amneziawg-go == self.packages.${system}.amneziawg-go;
    awgTools = (awgOverlay pkgs pkgs).amneziawg-tools == self.packages.${system}.amneziawg-tools;
    awgFamily = (self.lib.awgValidation { inherit lib; }).packageFamiliesValid {
      inherit (self.packages.${system}) amneziawg-go amneziawg-tools;
    };
    adguardOverride =
      overrideAttempt.machine.services.adguardhome.package == self.packages.${system}.adguardhome;
    unboundOverride =
      overrideAttempt.machine.services.unbound.package == self.packages.${system}.unbound;
    mihomoOverride =
      overrideAttempt.machine.networkCore.mihomo.packages == [ self.packages.${system}.mihomo ];
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
    && packageAuthority
    && dnsStatePreserved;
in
if contract then
  pkgs.runCommand "vpn-domain-contracts" { passthru = { inherit contract; }; } ''touch "$out"''
else
  throw "VPN domain contract failed: ${
    builtins.toJSON {
      inherit
        closedSchemas
        awgOverrideRejected
        dnsStatePreserved
        dnsStateResults
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
