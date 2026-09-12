{
  inputs,
  pkgs,
  self,
  system ? pkgs.system,
}:
let
  lib = inputs.nixpkgs.lib;
  fixture = import ./fixtures/example-clan.nix;
  privateDnsFixture = import ./fixtures/adguard-private-dns.nix;
  service = import ../clanServices/adguardhome/default.nix {
    adguardPackageFor = _: self.packages.${system}.adguardhome;
    dnsproxyPackageFor = _: self.packages.${system}.dnsproxy;
  };
  interface = service.roles.resolver.interface { inherit lib; };
  fixtureSettings = fixture.instances.dns-adguardhome.roles.resolver.machines.vpn-fixture.settings;
  baseSettings =
    lib.recursiveUpdate
      (
        (builtins.removeAttrs fixtureSettings [
          "acme"
          "ingress"
        ])
        // {
          ui = builtins.removeAttrs fixtureSettings.ui [ "domain" ];
        }
      )
      {
        tls = {
          certificateFile = "/run/certificates/adguardhome/fullchain.pem";
          privateKeyFile = "/run/certificates/adguardhome/key.pem";
        };
      };
  evalSettings =
    rawSettings:
    (lib.evalModules {
      modules = [
        interface
        { config = rawSettings; }
      ];
    }).config;
  schemaAccepts =
    rawSettings: (builtins.tryEval (builtins.deepSeq (evalSettings rawSettings) true)).success;
  render =
    rawSettings:
    let
      settings = evalSettings rawSettings;
      module =
        (service.roles.resolver.perInstance {
          inherit settings;
          instanceName = "dns-adguardhome";
          machine.name = "vpn-fixture";
        }).nixosModule
          {
            config = {
              clanwright.dns.adguardhome.activeInstances = [ "dns-adguardhome" ];
              sops.placeholder.${settings.auth.passwordSecretName} = "<SOPS:fixture-adguard-bcrypt:PLACEHOLDER>";
            };
            inherit lib pkgs;
          };
    in
    builtins.fromJSON module.config.sops.templates."dns-adguardhome-adguardhome.yaml".content;
  withPolicy =
    safeSearch: youtubeRestrictedMode:
    lib.recursiveUpdate baseSettings {
      filtering = { inherit safeSearch youtubeRestrictedMode; };
    };
  rendered = {
    defaults = render baseSettings;
    disabled = render (withPolicy false false);
    searchOnly = render (withPolicy true false);
    youtubeOnly = render (withPolicy false true);
    both = render (withPolicy true true);
  };
  searchFields = [
    "bing"
    "duckduckgo"
    "ecosia"
    "google"
    "pixabay"
    "yandex"
  ];
  policyMatches =
    effective: safeSearch: youtubeRestrictedMode:
    effective.filtering.safe_search.enabled == (safeSearch || youtubeRestrictedMode)
    && effective.filtering.safe_search.youtube == youtubeRestrictedMode
    && builtins.all (name: effective.filtering.safe_search.${name} == safeSearch) searchFields;
  privateSettings = lib.recursiveUpdate baseSettings {
    dns = privateDnsFixture;
    filtering.userRules = [ "||telemetry.example.invalid^" ];
  };
  privateBaseline = render privateSettings;
  privateYoutube = render (
    lib.recursiveUpdate privateSettings {
      filtering = {
        safeSearch = false;
        youtubeRestrictedMode = true;
      };
    }
  );
  privateClosure = effective: {
    inherit (effective) user_rules;
    dns = {
      inherit (effective.dns) blocked_hosts fallback_dns upstream_dns;
    };
    filtering.rewrites = effective.filtering.rewrites;
  };
  schemaContract =
    (evalSettings baseSettings).filtering.safeSearch
    && !(evalSettings baseSettings).filtering.youtubeRestrictedMode
    && schemaAccepts (withPolicy false true)
    && !(schemaAccepts (lib.recursiveUpdate baseSettings { filtering.safeSearch = "true"; }))
    && !(schemaAccepts (
      lib.recursiveUpdate baseSettings { filtering.youtubeRestrictedMode = "false"; }
    ));
  renderingContract =
    policyMatches rendered.defaults true false
    && policyMatches rendered.disabled false false
    && policyMatches rendered.searchOnly true false
    && policyMatches rendered.youtubeOnly false true
    && policyMatches rendered.both true true;
  privateClosureContract = privateClosure privateBaseline == privateClosure privateYoutube;
  contract = schemaContract && renderingContract && privateClosureContract;
in
if !contract then
  throw "AdGuard Home Safe Search contract failed: ${
    builtins.toJSON {
      inherit privateClosureContract renderingContract schemaContract;
    }
  }"
else
  {
    all = true;
    inherit privateClosureContract renderingContract schemaContract;
  }
