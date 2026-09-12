{
  inputs,
  pkgs,
  self,
  root ? ../.,
  system ? pkgs.system,
}:
let
  rawResults = {
    domain-contracts = import ./domain-contracts.nix {
      inherit
        inputs
        pkgs
        root
        self
        system
        ;
    };
    client-render-contracts = import ./client-render-smoke.nix {
      inherit
        inputs
        pkgs
        root
        self
        ;
    };
    package-authority-contracts = import ./package-authority-contracts.nix {
      inherit inputs self system;
    };
    provider-contracts = import ./provider-contracts.nix {
      inherit inputs;
    };
    publisher-manifest-contracts = import ./publisher-manifest-contracts.nix {
      inherit pkgs;
    };
    unbound-contracts = import ./unbound-contracts.nix {
      inherit
        inputs
        pkgs
        self
        system
        ;
    };
    naiveproxy-contracts = import ./naiveproxy-contracts.nix {
      inherit
        inputs
        pkgs
        root
        self
        ;
    };
    adguardhome-contracts = import ./adguardhome-contracts.nix {
      inherit
        inputs
        pkgs
        root
        self
        system
        ;
    };
    adguard-safe-search-contracts = import ./adguard-safe-search-contracts.nix {
      inherit
        inputs
        pkgs
        self
        system
        ;
    };
    xray-contracts = import ./xray-contracts.nix {
      inherit
        inputs
        pkgs
        root
        self
        system
        ;
    };
    hysteria-contracts = import ./hysteria-contracts.nix {
      inherit
        inputs
        pkgs
        self
        system
        ;
    };
    mieru-contracts = import ./mieru-contracts.nix {
      inherit
        inputs
        pkgs
        self
        system
        ;
    };
    awg-contracts = import ./awg-contracts.nix {
      inherit
        inputs
        pkgs
        root
        self
        system
        ;
    };
  };
  allBooleansTrue =
    value:
    if builtins.isBool value then
      value
    else if builtins.isAttrs value then
      builtins.all allBooleansTrue (builtins.attrValues value)
    else if builtins.isList value then
      builtins.all allBooleansTrue value
    else
      throw "evaluationTests results must contain only booleans, attribute sets and lists";
  checkResult =
    name: value:
    if builtins.deepSeq value (allBooleansTrue value) then
      value
    else
      throw "Pure Nix evaluation contract '${name}' returned a false diagnostic";
  resultCheckerContracts = {
    falseDiagnosticRejected =
      !(builtins.tryEval (
        builtins.deepSeq (checkResult "false-diagnostic" {
          contract = true;
          diagnostic = false;
        }) true
      )).success;
    nonBooleanDiagnosticRejected =
      !(builtins.tryEval (
        builtins.deepSeq (checkResult "non-boolean-diagnostic" { diagnostic = "pass"; }) true
      )).success;
  };
  results = builtins.mapAttrs checkResult (
    rawResults
    // {
      result-checker-contracts = resultCheckerContracts;
    }
  );
in
{
  inherit results;
  all = builtins.deepSeq results true;
}
