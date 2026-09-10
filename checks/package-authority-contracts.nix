{
  inputs,
  self,
  system,
}:
let
  lib = inputs.nixpkgs.lib;
  appsPkgs = import inputs.apps-nixpkgs { inherit system; };
  modernAppsPkgs = import inputs.modern-apps-nixpkgs { inherit system; };
  packageSpecs = {
    mihomo = {
      package = appsPkgs.mihomo;
      version = "1.19.30";
    };
    xray = {
      package = appsPkgs.xray;
      version = "26.3.27";
    };
    adguardhome = {
      package = appsPkgs.adguardhome;
      version = "0.107.78";
    };
    dnsproxy = {
      package = appsPkgs.dnsproxy;
      version = "0.83.2";
    };
    unbound = {
      package = appsPkgs.unbound-with-systemd;
      version = "1.26.0";
    };
    sing-box = {
      package = modernAppsPkgs.sing-box;
      version = "1.14.0";
    };
    amneziawg-go = {
      package = modernAppsPkgs.amneziawg-go;
      version = "3.1.20260828";
    };
    amneziawg-tools = {
      package = modernAppsPkgs.amneziawg-tools;
      version = "3.1.20260812";
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
