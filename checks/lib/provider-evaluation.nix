{ inputs }:
{
  instance,
  settings,
  prefix,
  extraModule ? { },
  system ? "x86_64-linux",
  baseModule ? { },
}:
let
  lib = inputs.nixpkgs.lib;
  ownedLocation = "${prefix}-fixture-owned";
  evaluated = lib.nixosSystem {
    inherit system;
    modules = [
      (lib.setDefaultModuleLocation ownedLocation instance.nixosModule)
      inputs.clan-core.inputs.sops-nix.nixosModules.sops
      ({ lib, ... }: {
        options.clan.core.state = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options.folders = lib.mkOption { type = lib.types.listOf lib.types.str; };
            }
          );
          default = { };
        };
        config = {
          nixpkgs.pkgs = inputs.nixpkgs.legacyPackages.${system};
          boot.isContainer = true;
          system.stateVersion = "26.11";
          networking = {
            nameservers = settings.dnsResolverIPv4s;
            firewall = {
              enable = true;
              backend = "nftables";
            };
            nftables.enable = true;
          };
          sops = {
            defaultSopsFile = ../fixtures/empty-sops.yaml;
            age.keyFile = "/run/vpn-fixture/age-key";
            validateSopsFiles = false;
            useSystemdActivation = true;
          };
        };
      })
      (lib.mkIf settings.enable baseModule)
      extraModule
    ];
  };
  module = evaluated.config;
  # Select owned definitions before reading diagnostics. Successful native
  # assertions may refer to failure-only values in their lazy messages.
  assertions = lib.concatMap (definition: definition.value) (
    builtins.filter (
      definition: definition.file == ownedLocation
    ) evaluated.options.assertions.definitionsWithLocations
  );
  ownedValues = map (entry: entry.assertion) assertions;
  nativeValues = map (entry: entry.assertion) module.assertions;
in
{
  inherit module assertions;
  inherit (evaluated) pkgs;
  assertionsPass = builtins.deepSeq ownedValues (
    (!settings.enable || assertions != [ ]) && builtins.all (value: value) ownedValues
  );
  nativeAssertionsPass = builtins.deepSeq nativeValues (builtins.all (value: value) nativeValues);
  rejects =
    message:
    let
      matches = builtins.filter (entry: entry.message == "${prefix}: ${message}") assertions;
      values = map (entry: entry.assertion) matches;
    in
    builtins.deepSeq values (builtins.length values == 1 && !(builtins.head values));
}
