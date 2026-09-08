{
  description = "Clanwright VPN and DNS domain services";

  inputs = {
    # Preserve the consumer's current platform and application closures for v0.1.0.
    nixpkgs.url = "https://releases.nixos.org/nixpkgs/nixpkgs-26.11pre1044894.59ea0b1c043c/nixexprs.tar.xz";
    apps-nixpkgs.url = "github:NixOS/nixpkgs/c27cdad491a991b11ed731760aa2ef8db0cb0410";
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
      domainAppsPkgsFor =
        system:
        let
          appsPkgs = appsPkgsFor system;
        in
        appsPkgs
        // {
          inherit (self.packages.${system}) sing-box;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          inherit (self.packages.${system})
            amneziawg-go
            amneziawg-tools
            ;
        };
      service = path: args: lib.modules.importApply path args;
      packageSet =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          appsPkgs = appsPkgsFor system;
        in
        {
          inherit (appsPkgs) mihomo;
          inherit (appsPkgs) sing-box;
          mihomo-keygen = appsPkgs.writeShellApplication {
            name = "mihomo-keygen";
            runtimeInputs = [ appsPkgs.mihomo ];
            text = ''
              exec mihomo generate reality-keypair
            '';
          };
        }
        // lib.optionalAttrs (system == "x86_64-linux") (
          {
            inherit (appsPkgs)
              amneziawg-go
              amneziawg-tools
              ;
            inherit (pkgs) adguardhome;
            unbound = appsPkgs.unbound-with-systemd;
          }
          // (import ./packages/naiveproxy.nix {
            inherit system;
            inherit apps-nixpkgs;
          })
          // (import ./packages/sing-box.nix {
            inherit system;
            inherit apps-nixpkgs;
          })
        );
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
            mihomoPackageFor = system: self.packages.${system}.mihomo;
          };
          "@clanwright/vpn-mihomo-hysteria2" = service ./clanServices/mihomo-hysteria2/default.nix {
            inherit lib;
            mihomoPackageFor = system: self.packages.${system}.mihomo;
          };
          "@clanwright/vpn-amneziawg" = service ./clanServices/amneziawg/default.nix {
            inherit lib;
            appsPkgsFor = domainAppsPkgsFor;
          };
          "@clanwright/vpn-naiveproxy" = service ./clanServices/naiveproxy/default.nix { inherit lib; };
          "@clanwright/vpn-client-profiles" = service ./clanServices/vpn-client-profiles/default.nix {
            inherit lib;
            clanLib = clan-core.lib;
            appsPkgsFor = domainAppsPkgsFor;
            mihomoPackageFor = system: self.packages.${system}.mihomo;
          };
          "@clanwright/dns-adguardhome" = service ./clanServices/adguardhome/default.nix {
            adguardPackageFor = system: self.packages.${system}.adguardhome;
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
        awgPublicKeyCheck =
          { pkgs }:
          import ./clanServices/amneziawg/public-key-check.nix {
            pkgs = pkgs // {
              inherit (self.packages.${pkgs.system}) amneziawg-tools;
            };
          };
        clientProfiles =
          {
            config,
            lib,
            pkgs,
            settings,
            gatewayProfiles,
          }:
          import ./clanServices/vpn-client-profiles/client-profiles.nix {
            appsPkgs = domainAppsPkgsFor pkgs.system;
            mihomoPackage = self.packages.${pkgs.system}.mihomo;
            inherit
              config
              lib
              pkgs
              settings
              gatewayProfiles
              ;
          };
        inherit exportInterfaces;
      };

      packages = forAllSystems packageSet;

      checks.x86_64-linux = import ./checks {
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
