{
  inputs,
  pkgs,
}:
let
  lib = inputs.nixpkgs.lib;
  service = import ../clanServices/naiveproxy/default.nix { inherit lib; };
  interface = service.roles.addon.interface { inherit lib; };
  baseSettings = {
    enable = true;
    selectedPublicSiteClaim = "fixture-site";
    selectedPublicSiteEndpoint = {
      domain = "site.example.invalid";
      publicIPv4 = "192.0.2.10";
      caddyBindIPv4 = "192.0.2.10";
    };
    passwordSecretNames = {
      ibelyasov = "fixture/naive-first-password";
      bsv = "fixture/naive-second-password";
      probe = "fixture/naive-probe-password";
    };
    additionalDeny = [ "203.0.113.77/32" ];
  };
  evalSettings =
    value:
    (lib.evalModules {
      modules = [
        interface
        { config = value; }
      ];
    }).config;
  schemaAccepts = value: (builtins.tryEval (builtins.deepSeq (evalSettings value) true)).success;
  claims = {
    fixture-site = {
      hostName = "site.example.invalid";
      listenAddresses = [ "192.0.2.10" ];
      publicSite = true;
    };
    sibling-site = {
      hostName = "sibling.example.invalid";
      listenAddresses = [ "192.0.2.10" ];
      publicSite = true;
    };
    tailnet-site = {
      hostName = "tailnet.example.invalid";
      listenAddresses = [ "100.64.0.10" ];
      publicSite = false;
    };
  };
  evaluate =
    rawSettings: claimSet: useSystemdActivation:
    let
      settings = evalSettings rawSettings;
      secretNames = builtins.attrValues settings.passwordSecretNames;
      config = {
        networkCore.caddy.fragments = claimSet;
        services.caddy = {
          configFile = "/etc/caddy/caddy_config";
          package = pkgs.caddy;
          user = "caddy";
          group = "caddy";
          environmentFile = null;
          enableReload = true;
          adapter = "caddyfile";
          resume = false;
          virtualHosts = { };
        };
        sops = {
          inherit useSystemdActivation;
          placeholder = lib.genAttrs secretNames (name: "<SOPS:${name}:PLACEHOLDER>");
          templates."naiveproxy-fixture.caddy".path = "/run/secrets/rendered/naiveproxy-fixture.caddy";
          secrets = lib.genAttrs secretNames (name: {
            path = "/run/secrets/${name}";
          });
        };
      };
      instance = service.roles.addon.perInstance {
        inherit settings;
        instanceName = "fixture--naiveproxy";
        machine.name = "fixture";
      };
      module = instance.nixosModule { inherit config lib pkgs; };
    in
    {
      inherit instance module settings;
      assertionsPass = builtins.all (entry: entry.assertion) module.assertions;
    };
  legacy = evaluate baseSettings claims true;
  activationScriptMode = evaluate baseSettings claims false;
  arbitrary = evaluate (
    baseSettings
    // {
      passwordSecretNames = {
        phone-android = "fixture/naive-phone-password";
        macbook = "fixture/naive-macbook-password";
        health-check = "fixture/naive-health-password";
      };
      probeUserName = "health-check";
    }
  ) claims true;
  nonPublic = evaluate baseSettings (claims // { fixture-site.publicSite = false; }) true;
  wrongEndpoint = evaluate (
    baseSettings
    // {
      selectedPublicSiteEndpoint = baseSettings.selectedPublicSiteEndpoint // {
        domain = "wrong.example.invalid";
      };
    }
  ) claims true;
  mixedSelectedListener = evaluate baseSettings (
    claims
    // {
      fixture-site.listenAddresses = [
        "192.0.2.10"
        "100.64.0.10"
      ];
    }
  ) true;
  missingProbe = evaluate (
    baseSettings
    // {
      passwordSecretNames = {
        phone = "fixture/naive-phone-password";
        laptop = "fixture/naive-laptop-password";
      };
    }
  ) claims true;
  contributions = legacy.module.networkCore.caddy.contributions;
  selectedPrelude = contributions.fixture-site.preRouteConfigFragments;
  siblingPrelude = contributions.sibling-site.preRouteConfigFragments;
  tailnetPrelude = contributions.tailnet-site.preRouteConfigFragments;
  template = legacy.module.sops.templates."naiveproxy-fixture.caddy";
  contract =
    legacy.assertionsPass
    && activationScriptMode.assertionsPass
    && arbitrary.assertionsPass
    && legacy.instance.exports.vpnProvider.schemaVersion == 2
    && arbitrary.instance.exports.vpnProvider.schemaVersion == 2
    &&
      legacy.instance.exports.vpnProvider.transportMetadata.userNames == [
        "bsv"
        "ibelyasov"
        "probe"
      ]
    &&
      legacy.instance.exports.vpnProvider.profileNames == [
        "bsv"
        "ibelyasov"
      ]
    &&
      arbitrary.instance.exports.vpnProvider.transportMetadata.userNames == [
        "health-check"
        "macbook"
        "phone-android"
      ]
    &&
      arbitrary.instance.exports.vpnProvider.profileNames == [
        "macbook"
        "phone-android"
      ]
    && !nonPublic.assertionsPass
    && !wrongEndpoint.assertionsPass
    && !mixedSelectedListener.assertionsPass
    && !missingProbe.assertionsPass
    && !(schemaAccepts (baseSettings // { machineName = "legacy-machine"; }))
    && !(schemaAccepts (
      baseSettings
      // {
        passwordSecretNames = {
          "bad identity" = "fixture/one";
          probe = "fixture/two";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        passwordSecretNames = {
          phone = "fixture/../secret";
          probe = "fixture/two";
        };
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        passwordSecretNames = {
          phone = "fixture/shared";
          probe = "fixture/shared";
        };
      }
    ))
    && !(schemaAccepts (baseSettings // { additionalDeny = [ "127.0.0.1\nallow all" ]; }))
    && !(schemaAccepts (baseSettings // { additionalDeny = [ "admin.example.invalid" ]; }))
    && !(schemaAccepts (baseSettings // { additionalDeny = [ "01.2.3.4" ]; }))
    && !(schemaAccepts (baseSettings // { additionalDeny = [ "999999999999999999999.2.3.4" ]; }))
    && !(schemaAccepts (
      lib.recursiveUpdate baseSettings {
        selectedPublicSiteEndpoint.publicIPv4 = "192.0.2.999";
      }
    ))
    && !(schemaAccepts (
      lib.recursiveUpdate baseSettings {
        selectedPublicSiteEndpoint.caddyBindIPv4 = "not-an-ip";
      }
    ))
    && !(schemaAccepts (baseSettings // { additionalDeny = [ "2001:db8:::1/128" ]; }))
    && !(schemaAccepts (
      lib.recursiveUpdate baseSettings {
        selectedPublicSiteEndpoint.publicIPv4 = "192.0.2.999";
      }
    ))
    && !(schemaAccepts (
      lib.recursiveUpdate baseSettings {
        selectedPublicSiteEndpoint.caddyBindIPv4 = "listener.example.invalid";
      }
    ))
    && schemaAccepts (
      baseSettings
      // {
        additionalDeny = [
          "203.0.113.77"
          "203.0.113.0/24"
          "2001:db8::77"
          "2001:db8::/48"
        ];
      }
    )
    && selectedPrelude == [ "import /run/secrets/rendered/naiveproxy-fixture.caddy" ]
    && builtins.length siblingPrelude == 1
    && lib.hasInfix "method CONNECT" (builtins.head siblingPrelude)
    && lib.hasInfix ''{http.request.local.host} == "192.0.2.10"'' (builtins.head siblingPrelude)
    && lib.hasInfix ''{http.request.local.port} == "443"'' (builtins.head siblingPrelude)
    && tailnetPrelude == [ ]
    && contributions.fixture-site.siteAddress == ":443"
    && contributions.sibling-site.siteAddress == null
    && contributions.tailnet-site.siteAddress == null
    && contributions.fixture-site.wantsUnits == [ "sops-install-secrets.service" ]
    && contributions.fixture-site.afterUnits == [ "sops-install-secrets.service" ]
    && !(contributions.fixture-site ? requiresUnits)
    && activationScriptMode.module.networkCore.caddy.contributions.fixture-site.wantsUnits == [ ]
    && activationScriptMode.module.networkCore.caddy.contributions.fixture-site.afterUnits == [ ]
    && !(activationScriptMode.module.networkCore.caddy.contributions.fixture-site ? requiresUnits)
    && template.owner == "root"
    && template.group == "caddy"
    && template.mode == "0440"
    && template.reloadUnits == [ "caddy.service" ]
    && lib.hasInfix "basic_auth bsv <SOPS:fixture/naive-second-password:PLACEHOLDER>" template.content
    && lib.hasInfix "deny 0.0.0.0/8" template.content
    && lib.hasInfix "203.0.113.77/32" template.content
    && lib.hasInfix "100:0:0:1::/64" template.content
    && lib.hasInfix "2001:2::/48" template.content
    && lib.hasInfix "3fff::/20" template.content
    && lib.hasInfix "5f00::/16" template.content
    && lib.hasInfix "allow all" template.content
    && !(lib.hasInfix "ports 80 443" template.content)
    && lib.hasInfix "probe_resistance" template.content
    && (legacy.module.systemd.services or { }) == { }
    && builtins.all (secret: !(secret ? restartUnits) && !(secret ? reloadUnits)) (
      builtins.attrValues legacy.module.sops.secrets
    );
in
if !contract then
  throw "NaiveProxy contract, ACL, native-template, or listener-isolation check failed"
else
  {
    all = true;
    inherit contract;
  }
