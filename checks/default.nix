{
  inputs,
  pkgs,
  self,
  root ? ../.,
  system ? pkgs.system,
}:
let
  results = {
    domain-contracts = import ./domain-contracts.nix {
      inherit
        inputs
        pkgs
        root
        self
        system
        ;
    };
    combined-clan-fixture = import ./combined-clan-fixture.nix {
      inherit inputs root self;
    };
    client-render-contracts = import ./client-render-smoke.nix {
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
      inherit inputs pkgs;
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
  allPassed = builtins.deepSeq results (allBooleansTrue results);
in
{
  inherit results;
  all = if allPassed then true else throw "One or more pure Nix evaluation contracts failed";
}
