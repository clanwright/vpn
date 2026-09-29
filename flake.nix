{
  description = "Clanwright VPN and DNS domain services";

  inputs = {
    # Separate platform and reviewed stock application revisions.
    nixpkgs.url = "github:NixOS/nixpkgs/8d5d270900d3fc75655ea2d9d248b234f6631439";
    apps-nixpkgs.url = "github:NixOS/nixpkgs/8d5d270900d3fc75655ea2d9d248b234f6631439";
    modern-apps-nixpkgs.url = "github:NixOS/nixpkgs/8d5d270900d3fc75655ea2d9d248b234f6631439";
    trusttunnel-nixpkgs.url = "github:NixOS/nixpkgs/8d5d270900d3fc75655ea2d9d248b234f6631439";
    # Test/integration dependency only; VPN does not re-export or enable it.
    # Network v4.0.0.
    network.url = "github:clanwright/network/2981962f1f590fae66c05c50a3d793825281de9e";
    data-mesher.url = "path:./stubs/data-mesher";
    clan-core = {
      url = "github:clan-lol/clan-core/c612dac4b2bfb5278b7c366f250044ddb5401bcb";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        data-mesher.follows = "data-mesher";
        sops-nix = {
          url = "github:Mic92/sops-nix/5efb5a6f4f5ab192817d28557dd4d650fa14d866";
          inputs.nixpkgs.follows = "nixpkgs";
        };
      };
    };
  };

  outputs =
    inputs@{
      self,
      apps-nixpkgs,
      clan-core,
      modern-apps-nixpkgs,
      nixpkgs,
      trusttunnel-nixpkgs,
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
      trustTunnelPkgsFor = system: import trusttunnel-nixpkgs { inherit system; };
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
          inherit (modernAppsPkgs) amneziawg-go amneziawg-tools mieru;
          inherit (trustTunnelPkgsFor system) trusttunnel-endpoint;
          unbound = appsPkgs.unbound-with-systemd;
        };
      exportInterfaces =
        { lib }:
        {
          vpnProvider = (import ./modules/contracts/vpn-exports.nix { inherit lib; }).vpnProviderModule;
        };
    in
    {
      clan = {
        modules = {
          "@clanwright/vpn-mihomo-vless-xhttp" = service ./clanServices/mihomo-vless-xhttp/default.nix {
            inherit lib;
            xrayPackageFor = system: self.packages.${system}.xray;
          };
          "@clanwright/vpn-mieru" = service ./clanServices/mieru/default.nix {
            inherit lib;
            mieruPackageFor = system: self.packages.${system}.mieru;
          };
          "@clanwright/vpn-anytls" = service ./clanServices/anytls/default.nix {
            inherit lib;
            singBoxPackageFor = system: self.packages.${system}.sing-box;
          };
          "@clanwright/vpn-trusttunnel" = service ./clanServices/trusttunnel/default.nix {
            inherit lib;
            trustTunnelPackageFor = system: self.packages.${system}.trusttunnel-endpoint;
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
