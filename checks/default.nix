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
    client-render-contracts = import ./client-render-contracts.nix {
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
    external-subscriptions-contracts = import ./external-subscriptions-contracts.nix {
      inherit inputs root self;
    };
    display-names-contracts = import ./display-names-contracts.nix {
      inherit
        inputs
        pkgs
        root
        self
        ;
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
    mieru-contracts = import ./mieru-contracts.nix {
      inherit
        inputs
        pkgs
        self
        system
        ;
    };
    anytls-contracts = import ./anytls-contracts.nix {
      inherit
        inputs
        pkgs
        self
        system
        ;
    };
    trusttunnel-contracts = import ./trusttunnel-contracts.nix {
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
  # This independent inventory makes accidental deletion of an import fail.
  expectedSuites = [
    "adguard-safe-search-contracts"
    "adguardhome-contracts"
    "anytls-contracts"
    "awg-contracts"
    "client-render-contracts"
    "display-names-contracts"
    "domain-contracts"
    "external-subscriptions-contracts"
    "mieru-contracts"
    "naiveproxy-contracts"
    "package-authority-contracts"
    "provider-contracts"
    "publisher-manifest-contracts"
    "result-checker-contracts"
    "trusttunnel-contracts"
    "unbound-contracts"
    "xray-contracts"
  ];
  checkInventory =
    expected: suites:
    if expected != [ ] && builtins.attrNames suites == expected then
      suites
    else
      throw "evaluationTests suite inventory is empty, missing or unexpected";
  allBooleansTrue =
    value:
    if builtins.isBool value then
      value
    else if builtins.isAttrs value then
      value != { } && builtins.all allBooleansTrue (builtins.attrValues value)
    else if builtins.isList value then
      value != [ ] && builtins.all allBooleansTrue value
    else
      throw "evaluationTests results must contain only booleans, attribute sets and lists";
  resultIsTrue = value: builtins.deepSeq value (allBooleansTrue value);
  checkResult =
    name: value:
    if resultIsTrue value then
      value
    else
      throw "Pure Nix evaluation contract '${name}' returned a false diagnostic";
  resultCheckerContracts = {
    emptySuiteRejected = !(builtins.tryEval (checkResult "empty-suite" { })).success;
    emptyListRejected = !(builtins.tryEval (checkResult "empty-list" [ ])).success;
    emptyInventoryRejected = !(builtins.tryEval (checkInventory [ ] { })).success;
    missingSuiteRejected = !(builtins.tryEval (checkInventory [ "required-contracts" ] { })).success;
    unexpectedSuiteRejected =
      !(builtins.tryEval (
        checkInventory [ "required-contracts" ] {
          required-contracts = true;
          unexpected-contracts = true;
        }
      )).success;
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
    nestedNonBooleanRejected =
      !(builtins.tryEval (
        builtins.deepSeq (checkResult "nested-non-boolean" { nested = [ { diagnostic = null; } ]; }) true
      )).success;
    allLeavesForced =
      !(builtins.tryEval (resultIsTrue {
        first = false;
        later = throw "every leaf must be forced";
      })).success;
  };
  results = builtins.mapAttrs checkResult (
    checkInventory expectedSuites (
      rawResults
      // {
        result-checker-contracts = resultCheckerContracts;
      }
    )
  );
in
{
  inherit results;
  moduleNames = builtins.attrNames self.clan.modules;
  packageNames = builtins.attrNames self.packages.${system};
  all = builtins.deepSeq results true;
}
