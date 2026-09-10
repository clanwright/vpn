{
  description = "Clanwright VPN and DNS domain services";

  inputs = {
    # Separate platform and reviewed stock application revisions.
    nixpkgs.url = "https://releases.nixos.org/nixpkgs/nixpkgs-26.11pre1044894.59ea0b1c043c/nixexprs.tar.xz";
    apps-nixpkgs.url = "github:NixOS/nixpkgs/c27cdad491a991b11ed731760aa2ef8db0cb0410";
    modern-apps-nixpkgs.url = "github:NixOS/nixpkgs/f3afd85cd82edf71f2dea9b96dcda2d6a64f26f4";
    # Test/integration dependency only; VPN does not re-export or enable it.
    network.url = "github:clanwright/network/v1.0.0";
    data-mesher.url = "path:./stubs/data-mesher";
    clan-core = {
      url = "github:clan-lol/clan-core/3b5832a13fb0ad1e57c2dafd246ca8ab60ad1b20";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.data-mesher.follows = "data-mesher";
    };
  };

  outputs =
    inputs@{
      self,
      apps-nixpkgs,
      clan-core,
      modern-apps-nixpkgs,
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = lib.genAttrs systems;
      appsPkgsFor = system: import apps-nixpkgs { inherit system; };
      modernAppsPkgsFor = system: import modern-apps-nixpkgs { inherit system; };
      service = path: args: lib.modules.importApply path args;
      packageSet =
        system:
        let
          appsPkgs = appsPkgsFor system;
          modernAppsPkgs = modernAppsPkgsFor system;
        in
        {
          inherit (appsPkgs) mihomo;
          inherit (modernAppsPkgs) sing-box;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          inherit (appsPkgs)
            adguardhome
            dnsproxy
            xray
            ;
          inherit (modernAppsPkgs) amneziawg-go amneziawg-tools;
          unbound = appsPkgs.unbound-with-systemd;
        };
      vpnExports = { lib }: import ./modules/contracts/vpn-exports.nix { inherit lib; };
      exportInterfaces =
        { lib }:
        let
          exports = vpnExports { inherit lib; };
        in
        {
          vpnProvider = exports.vpnProviderModule;
          vpnPublisher = exports.vpnPublisherModule;
        };
    in
    {
      clan = {
        modules = {
          "@clanwright/vpn-mihomo-vless-xhttp" = service ./clanServices/mihomo-vless-xhttp/default.nix {
            inherit lib;
            xrayPackageFor = system: self.packages.${system}.xray;
          };
          "@clanwright/vpn-mihomo-hysteria2" = service ./clanServices/mihomo-hysteria2/default.nix {
            inherit lib;
            mihomoPackageFor = system: self.packages.${system}.mihomo;
          };
          "@clanwright/vpn-amneziawg" = service ./clanServices/amneziawg/default.nix {
            inherit lib;
            appsPkgsFor = system: self.packages.${system};
          };
          "@clanwright/vpn-naiveproxy" = service ./clanServices/naiveproxy/default.nix { inherit lib; };
          "@clanwright/vpn-client-profiles" = service ./clanServices/vpn-client-profiles/default.nix {
            inherit lib;
            clanLib = clan-core.lib;
            appsPkgsFor = system: self.packages.${system};
            mihomoPackageFor = system: self.packages.${system}.mihomo;
          };
          "@clanwright/dns-adguardhome" = service ./clanServices/adguardhome/default.nix {
            adguardPackageFor = system: self.packages.${system}.adguardhome;
            dnsproxyPackageFor = system: self.packages.${system}.dnsproxy;
          };
          "@clanwright/dns-unbound" = service ./clanServices/unbound/default.nix {
            unboundPackageFor = system: self.packages.${system}.unbound;
          };
        };
        exportInterfaces = exportInterfaces { inherit lib; };
      };

      clanModule = { lib, ... }: {
        exportInterfaces = exportInterfaces { inherit lib; };
      };

      lib = {
        inherit vpnExports;
        awgValidation = { lib }: import ./clanServices/amneziawg/validation.nix { inherit lib; };
        clientProfiles =
          {
            config,
            lib,
            pkgs,
            settings,
            providers,
          }:
          import ./clanServices/vpn-client-profiles/client-profiles.nix {
            appsPkgs = self.packages.${pkgs.system};
            mihomoPackage = self.packages.${pkgs.system}.mihomo;
            inherit
              config
              lib
              pkgs
              settings
              providers
              ;
          };
        inherit exportInterfaces;
      };

      packages = forAllSystems packageSet;

      evaluationTests.x86_64-linux = import ./checks {
        inherit inputs self;
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.deadnix
              pkgs.gitleaks
              pkgs.nixfmt
              pkgs.statix
            ];
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
