{ inputs, self }:
instances:
let
  inherit (inputs.nixpkgs) lib;
  policy = import ../../modules/contracts/protocol-policy.nix;
  exportFor =
    _protocol: metadata:
    let
      instanceName = lib.removePrefix "@clanwright/" metadata.service;
      service = builtins.head self.clan.modules.${metadata.service}.imports;
      machineName = "vpn-fixture";
      settings =
        (lib.evalModules {
          modules = [
            (service.roles.${metadata.role}.interface { inherit lib; })
            { config = instances.${instanceName}.roles.${metadata.role}.machines.${machineName}.settings; }
          ];
        }).config;
      instance = service.roles.${metadata.role}.perInstance {
        inherit settings instanceName;
        machine.name = machineName;
        mkExports = value: value;
      };
    in
    lib.nameValuePair (inputs.clan-core.lib.buildScopeKey {
      serviceName = metadata.service;
      roleName = metadata.role;
      inherit machineName instanceName;
    }) instance.exports;
in
lib.mapAttrs' exportFor policy.protocols
