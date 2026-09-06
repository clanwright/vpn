{
  inputs,
  root,
  self,
}:
let
  fixture = import ../fixtures/example-clan.nix;
in
{
  instanceNames,
  extraModule ? { },
}:
let
  supportInstances = [
    "edge-wildcard-certificate"
    "network-caddy"
    "network-certificates"
  ];
  rawSelectedInstances = builtins.intersectAttrs (inputs.nixpkgs.lib.genAttrs (
    supportInstances ++ instanceNames
  ) (_: null)) fixture.instances;
  selectedInstances =
    if instanceNames == [ "vpn-client-profiles" ] then
      rawSelectedInstances
      // {
        vpn-client-profiles = inputs.nixpkgs.lib.recursiveUpdate rawSelectedInstances.vpn-client-profiles {
          roles.publisher.machines.vpn-fixture.settings.enable = false;
        };
      }
    else
      rawSelectedInstances;
  consumer = inputs.clan-core.lib.clan {
    self.inputs = {
      vpn = self;
      inherit (inputs) network;
      self.clan = consumer.config;
    };
    specialArgs.clan-core = inputs.clan-core;
    directory = builtins.path {
      path = root + /checks/fixtures;
      name = "vpn-consumer-fixtures";
    };
    imports = [
      self.clanModule
      {
        machines.${fixture.machineName or "vpn-fixture"} =
          _:
          fixture.machine
          // {
            imports = (fixture.machine.imports or [ ]) ++ [ extraModule ];
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
