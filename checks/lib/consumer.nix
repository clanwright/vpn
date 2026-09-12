{
  inputs,
  root,
  self,
}:
let
  fixture = import ../fixtures/example-clan.nix;
in
{
  instanceNames ? null,
  instances ? null,
  instanceOverrides ? { },
  extraModule ? { },
  includeNetwork ? false,
  fixtureName ? "vpn-consumer-fixture",
}:
let
  lib = inputs.nixpkgs.lib;
  supportInstances = [
    "edge-wildcard-certificate"
    "network-caddy"
    "network-certificates"
  ];
  selectedSupportInstances = lib.optionals includeNetwork supportInstances;
  rawSelectedInstances =
    if instances != null then
      instances
    else
      builtins.intersectAttrs (lib.genAttrs (selectedSupportInstances ++ instanceNames) (
        _: null
      )) fixture.instances;
  selectedInstances = lib.recursiveUpdate rawSelectedInstances instanceOverrides;
  consumer = inputs.clan-core.lib.clan {
    self.inputs = {
      vpn = self;
      inherit (inputs) network;
      self.clan = consumer.config;
    };
    specialArgs.clan-core = inputs.clan-core;
    directory = builtins.path {
      path = root + /checks/fixtures;
      name = fixtureName;
    };
    imports = [
      self.clanModule
      {
        machines.${fixture.machineName or "vpn-fixture"} =
          _:
          fixture.machine
          // {
            imports =
              (fixture.machine.imports or [ ])
              ++ lib.optional includeNetwork fixture.networkIntegrationModule
              ++ [ extraModule ];
          };
        inventory = {
          meta.name = "vpn-consumer-fixture";
          machines.vpn-fixture = { };
          instances = selectedInstances;
        };
      }
    ];
  };
  machine = consumer.config.nixosConfigurations.vpn-fixture.config;
  assertionsPass = builtins.all (entry: entry.assertion) machine.assertions;
  evaluated = builtins.deepSeq (builtins.mapAttrs (_: unit: unit.text) machine.systemd.units) (
    builtins.seq machine.system.build.toplevel.drvPath assertionsPass
  );
in
assert evaluated;
{
  inherit machine;
  inherit (consumer) config;
}
