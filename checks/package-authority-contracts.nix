{
  inputs,
  self,
  system,
}:
let
  lib = inputs.nixpkgs.lib;
  stockPkgs = inputs.nixpkgs.legacyPackages.${system};
  packageSpecs = {
    mihomo = {
      package = stockPkgs.mihomo;
      version = "1.19.31";
    };
    xray = {
      package = stockPkgs.xray;
      version = "26.9.9";
    };
    adguardhome = {
      package = stockPkgs.adguardhome;
      version = "0.107.79";
    };
    dnsproxy = {
      package = stockPkgs.dnsproxy;
      version = "0.84.1";
    };
    unbound = {
      package = stockPkgs.unbound-with-systemd;
      version = "1.26.0";
    };
    sing-box = {
      package = stockPkgs.sing-box;
      version = "1.14.1";
    };
    mieru = {
      package = stockPkgs.mieru;
      version = "3.36.0";
    };
    amneziawg-go = {
      package = stockPkgs.amneziawg-go;
      version = "3.1.20260828";
    };
    amneziawg-tools = {
      package = stockPkgs.amneziawg-tools;
      version = "3.1.20260812";
    };
    trusttunnel-endpoint = {
      package = stockPkgs.trusttunnel-endpoint;
      version = "1.1.0";
    };
  };
  expectedNames = lib.sort builtins.lessThan (builtins.attrNames packageSpecs);
  actualNames = lib.sort builtins.lessThan (builtins.attrNames self.packages.${system});
  sourceResults = lib.mapAttrs (
    name: spec: self.packages.${system}.${name} == spec.package
  ) packageSpecs;
  versionResults = lib.mapAttrs (
    name: spec: self.packages.${system}.${name}.version == spec.version
  ) packageSpecs;
  packageSetExact = actualNames == expectedNames;
  contract =
    packageSetExact
    && builtins.all (value: value) (builtins.attrValues sourceResults)
    && builtins.all (value: value) (builtins.attrValues versionResults);
in
if !contract then
  throw "Exact stock package authority contract failed: ${
    builtins.toJSON {
      inherit packageSetExact sourceResults versionResults;
    }
  }"
else
  {
    all = true;
    inherit
      contract
      packageSetExact
      sourceResults
      versionResults
      ;
  }
