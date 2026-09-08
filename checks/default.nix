{
  inputs,
  pkgs,
  self,
  root ? ../.,
  system ? pkgs.system,
}:
{
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
    inherit
      inputs
      pkgs
      root
      self
      ;
  };
  client-render-smoke = import ./client-render-smoke.nix {
    inherit
      inputs
      pkgs
      root
      self
      ;
  };
  amneziawg-key-consistency = import ./amneziawg-key-consistency.nix {
    inherit pkgs self;
    lib = inputs.nixpkgs.lib;
  };
  unbound-readiness = import ./unbound-readiness.nix { inherit pkgs self; };
  unbound-contracts = import ./unbound-contracts.nix {
    inherit
      inputs
      pkgs
      self
      system
      ;
  };
  unbound-runtime = import ./unbound-runtime.nix { inherit pkgs self; };
  naiveproxy-contracts = import ./naiveproxy-contracts.nix {
    inherit inputs pkgs;
  };
}
