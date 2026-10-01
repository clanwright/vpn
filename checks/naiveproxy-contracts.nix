{
  inputs,
  pkgs,
  root,
  self,
}:
let
  lib = inputs.nixpkgs.lib;
  consumer = import ./lib/consumer.nix { inherit inputs root self; };
  service = import ../clanServices/naiveproxy/default.nix { inherit lib; };
  interface = service.roles.addon.interface { inherit lib; };
  baseSettings = {
    enable = true;
    domain = "site.example.invalid";
    publicIPv4 = "198.51.100.77";
    bindIPv4 = "192.0.2.10";
    passwordSecretNames = {
      ibelyasov = "fixture/naive-first-password";
      bsv = "fixture/naive-second-password";
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
  templateName = "naiveproxy-vpn-fixture.caddy";
  ownedLocation = "naiveproxy-fixture-owned";
  evaluate =
    {
      rawSettings ? baseSettings,
      extraModule ? { },
      useSystemdActivation ? true,
      additionalSettings ? [ ],
    }:
    let
      instanceFor =
        index: value:
        service.roles.addon.perInstance {
          settings = evalSettings value;
          instanceName = "fixture--naiveproxy-${toString index}";
          machine.name = "vpn-fixture";
        };
      instance = instanceFor 0 rawSettings;
      instances = [ instance ] ++ lib.imap1 instanceFor additionalSettings;
      result = consumer {
        instanceNames = [ ];
        includeNetwork = true;
        evaluateOnly = true;
        extraModule = {
          imports = map (item: lib.setDefaultModuleLocation ownedLocation item.nixosModule) instances ++ [
            ({ config, lib, ... }: {
              sops.useSystemdActivation = lib.mkForce useSystemdActivation;
              services.caddy.virtualHosts =
                lib.genAttrs
                  [
                    "cover.example.invalid"
                    "private.example.invalid"
                    "disjoint.example.invalid"
                  ]
                  (domain: {
                    owner = "fixture:${domain}";
                    listenAddresses =
                      if domain == "private.example.invalid" then
                        [ "100.64.0.10" ]
                      else if domain == "disjoint.example.invalid" then
                        [ "192.0.2.20" ]
                      else
                        [ "192.0.2.10" ];
                    useACMEHost = "fixture";
                    serverAliases = lib.optional (domain == "cover.example.invalid") "cover-alias.example.invalid";
                    # Explicit same-public-listener attachment is inside this
                    # native Host route. It does not move the outer Host matcher.
                    extraConfig = lib.mkMerge [
                      (lib.mkIf (domain == "cover.example.invalid") (
                        lib.mkBefore config.clanwright.vpn.naiveproxy.connectRoute
                      ))
                      (lib.mkIf (domain == "cover.example.invalid") (
                        lib.mkOrder 1000 ''
                          route {
                            @cover_alias host cover-alias.example.invalid
                            redir @cover_alias https://cover.example.invalid{uri} permanent
                          }
                        ''
                      ))
                      (lib.mkOrder 2000 ''
                        # cover-terminal-content
                        route { respond "cover" }
                      '')
                    ];
                  })
                // {
                  "unattached.example.invalid" = {
                    owner = "fixture:unattached";
                    listenAddresses = [ "192.0.2.30" ];
                    useACMEHost = "fixture";
                    extraConfig = lib.mkOrder 2000 ''route { respond "unattached" }'';
                  };
                };
            })
            extraModule
          ];
        };
      };
      inherit (result) machine;
      assertions = lib.concatMap (definition: definition.value) (
        builtins.filter (
          definition: definition.file == ownedLocation
        ) result.options.assertions.definitionsWithLocations
      );
      ownedValues = map (entry: entry.assertion) assertions;
      nativeValues = map (entry: entry.assertion) machine.assertions;
      rejects =
        message:
        let
          selected = builtins.filter (entry: entry.message == "naiveproxy: ${message}") assertions;
        in
        assert builtins.length selected == 1;
        !(builtins.head selected).assertion;
    in
    {
      inherit
        instance
        machine
        assertions
        rejects
        ;
      activeInstanceDefinitions =
        result.options.clanwright.vpn.naiveproxy.activeInstances.definitionsWithLocations;
      assertionsPass = builtins.deepSeq ownedValues (
        assertions != [ ] && builtins.all (value: value) ownedValues
      );
      nativeAssertionsPass = builtins.deepSeq nativeValues (builtins.all (value: value) nativeValues);
      template = machine.sops.templates.${templateName} or null;
      route = machine.clanwright.vpn.naiveproxy.connectRoute;
    };
  baseline = evaluate { };
  activationScriptMode = evaluate { useSystemdActivation = false; };
  arbitrary = evaluate {
    rawSettings = baseSettings // {
      passwordSecretNames = {
        phone-android = "fixture/naive-phone-password";
        macbook = "fixture/naive-macbook-password";
        tablet = "fixture/naive-tablet-password";
      };
    };
  };
  usersOnly = evaluate {
    rawSettings = baseSettings // {
      passwordSecretNames = {
        alice = "naiveproxy-alice-password";
        bob = "naiveproxy-bob-password";
      };
    };
  };
  disabled = evaluate {
    rawSettings = baseSettings // {
      enable = false;
    };
  };
  duplicateOwner = builtins.tryEval (
    builtins.deepSeq
      (evaluate {
        extraModule.services.caddy.virtualHosts.${baseSettings.domain}.owner = "fixture:second-owner";
      }).machine.services.caddy.virtualHosts.${baseSettings.domain}.owner
      true
  );
  duplicateProxy = builtins.tryEval (
    builtins.deepSeq
      (evaluate {
        extraModule.services.caddy.virtualHosts.${baseSettings.domain}.forwardProxy = true;
      }).machine.services.caddy.virtualHosts.${baseSettings.domain}.forwardProxy
      true
  );
  publicRouteRedefinition = builtins.tryEval (
    builtins.deepSeq
      (evaluate {
        extraModule.clanwright.vpn.naiveproxy.connectRoute = "route { respond 403 }";
      }).route
      true
  );
  missingBase = evaluate {
    rawSettings = baseSettings // {
      domain = "missing.example.invalid";
    };
  };
  activeWithDisabled = evaluate { additionalSettings = [ (baseSettings // { enable = false; }) ]; };
  duplicateInstances = evaluate {
    extraModule.clanwright.vpn.naiveproxy.activeInstances = lib.mkForce [
      "one"
      "two"
    ];
  };
  missingInstanceClaim = evaluate {
    extraModule.clanwright.vpn.naiveproxy.activeInstances = lib.mkForce [ ];
  };
  twoActive = evaluate { additionalSettings = [ baseSettings ]; };
  singletonMessage = "only one active instance may claim the machine-wide Caddy forward-proxy integration.";
  listenerMessage = "the selected native Caddy host must have an existing owner and exactly the declared isolated IPv4 listener on port 443.";
  policyMessage = "authenticated policy, SOPS credential permissions, and native Caddy reload bindings must remain guarded.";
  routeMessage = "selected authenticated CONNECT, in-memory credentials, and non-requiring SOPS startup dependencies must remain guarded.";
  runtimeMessage = "runtime credentials require native Caddyfile reload and resume disabled.";
  rejectsOverride = message: extraModule: (evaluate { inherit extraModule; }).rejects message;
  listenerOverrides = [
    { services.caddy.virtualHosts = lib.mkForce { }; }
    { services.caddy.virtualHosts.${baseSettings.domain}.listenAddresses = lib.mkForce [ ]; }
    { services.caddy.virtualHosts.${baseSettings.domain}.listenAddresses = lib.mkForce [ "0.0.0.0" ]; }
    {
      services.caddy.virtualHosts.${baseSettings.domain}.listenAddresses = lib.mkForce [
        "192.0.2.10"
        "100.64.0.10"
      ];
    }
    {
      services.caddy.virtualHosts.${baseSettings.domain}.listenAddresses = lib.mkForce [ "192.0.2.20" ];
    }
    { services.caddy.virtualHosts.${baseSettings.domain}.forwardProxy = lib.mkForce false; }
    {
      services.caddy.virtualHosts.${baseSettings.domain}.hostName = lib.mkForce "wrong.example.invalid";
    }
  ];
  policyOverrides = [
    { sops.templates = lib.mkForce { }; }
    { sops.templates.${templateName}.content = lib.mkForce "forward_proxy { allow all }"; }
    { sops.templates.${templateName}.mode = lib.mkForce "0444"; }
    { sops.templates.${templateName}.group = lib.mkForce "root"; }
    { sops.templates.${templateName}.reloadUnits = lib.mkForce [ ]; }
    { sops.secrets."fixture/naive-first-password".mode = lib.mkForce "0444"; }
    { sops.secrets."fixture/naive-first-password".path = lib.mkForce "/run/elsewhere"; }
  ];
  routeOverrides = [
    { clanwright.vpn.naiveproxy.connectRouteContent = lib.mkForce "route { respond 403 }"; }
    {
      services.caddy.virtualHosts.${baseSettings.domain}.extraConfig =
        lib.mkForce ''route { respond "unprotected" }'';
    }
    { services.caddy.globalConfig = lib.mkForce ""; }
    { systemd.services.caddy.wants = lib.mkForce [ ]; }
    { systemd.services.caddy.after = lib.mkForce [ ]; }
    { systemd.services.caddy.requires = lib.mkAfter [ "sops-install-secrets.service" ]; }
  ];
  runtimeOverrides = [
    { services.caddy.enableReload = lib.mkForce false; }
    { services.caddy.resume = lib.mkForce true; }
    { services.caddy.adapter = lib.mkForce "json"; }
    { services.caddy.httpsPort = lib.mkForce 8443; }
  ];
  overrideResults =
    map (rejectsOverride listenerMessage) listenerOverrides
    ++ map (rejectsOverride policyMessage) policyOverrides
    ++ map (rejectsOverride routeMessage) routeOverrides
    ++ map (rejectsOverride runtimeMessage) runtimeOverrides;
  dualSingletonAssertions = builtins.filter (
    entry: entry.message == "naiveproxy: ${singletonMessage}"
  ) twoActive.assertions;
  compositionResults = {
    baselineOwned = baseline.assertionsPass;
    baselineNative = baseline.nativeAssertionsPass;
    activationOwned = activationScriptMode.assertionsPass;
    activationNative = activationScriptMode.nativeAssertionsPass;
    arbitraryOwned = arbitrary.assertionsPass;
    arbitraryNative = arbitrary.nativeAssertionsPass;
    usersOnlyOwned = usersOnly.assertionsPass;
    usersOnlyNative = usersOnly.nativeAssertionsPass;
    activeDisabledOwned = activeWithDisabled.assertionsPass;
    activeDisabledNative = activeWithDisabled.nativeAssertionsPass;
    activeDisabledSingleton =
      activeWithDisabled.machine.clanwright.vpn.naiveproxy.activeInstances == [ "fixture--naiveproxy-0" ];
    duplicateClaim = duplicateInstances.rejects singletonMessage;
    missingClaim = missingInstanceClaim.rejects singletonMessage;
    duplicateOwner = !duplicateOwner.success;
    duplicateProxy = !duplicateProxy.success;
    publicReadOnly = !publicRouteRedefinition.success;
    missingBase = missingBase.rejects listenerMessage;
    dualSingletonCount = builtins.length dualSingletonAssertions == 2;
    dualDistinctClaims =
      lib.sort builtins.lessThan twoActive.machine.clanwright.vpn.naiveproxy.activeInstances == [
        "fixture--naiveproxy-0"
        "fixture--naiveproxy-1"
      ];
    dualOwnedDefinitions =
      builtins.length twoActive.activeInstanceDefinitions == 2
      && builtins.all (definition: definition.file == ownedLocation) twoActive.activeInstanceDefinitions;
    dualSingletonReject = builtins.deepSeq (map (entry: entry.assertion) dualSingletonAssertions) (
      builtins.all (entry: !entry.assertion) dualSingletonAssertions
    );
    allOverrides = builtins.deepSeq overrideResults (builtins.all (value: value) overrideResults);
  };
  compositionContract = builtins.deepSeq compositionResults (
    builtins.all (value: value) (builtins.attrValues compositionResults)
  );
  disabledContract =
    disabled.assertionsPass
    && disabled.nativeAssertionsPass
    && disabled.instance.exports == { }
    && disabled.route == ""
    && !(disabled.machine.sops.templates ? ${templateName})
    && !(disabled.machine.sops.secrets ? "fixture/naive-first-password")
    && !disabled.machine.services.caddy.virtualHosts.${baseSettings.domain}.forwardProxy;
  exportContract =
    usersOnly.instance.exports.vpnProvider == {
      schemaVersion = 3;
      connection.naiveproxy = {
        endpoint = {
          hostname = "site.example.invalid";
          ipv4 = "198.51.100.77";
          port = 443;
        };
        clients = {
          alice.passwordSecret = "naiveproxy-alice-password";
          bob.passwordSecret = "naiveproxy-bob-password";
        };
      };
    }
    &&
      builtins.attrNames arbitrary.instance.exports.vpnProvider.connection.naiveproxy.clients == [
        "macbook"
        "phone-android"
        "tablet"
      ];
  schemaResults = map (value: !(schemaAccepts value)) [
    (builtins.removeAttrs baseSettings [ "domain" ])
    (builtins.removeAttrs baseSettings [ "publicIPv4" ])
    (builtins.removeAttrs baseSettings [ "bindIPv4" ])
    (baseSettings // { selectedPublicSiteClaim = "old"; })
    (
      baseSettings
      // {
        selectedPublicSiteEndpoint = {
          domain = "old.example.invalid";
        };
      }
    )
    (baseSettings // { probeUserName = "probe"; })
    (baseSettings // { machineName = "old"; })
    (baseSettings // { domain = "Site.example.invalid"; })
    (baseSettings // { domain = "site.example.invalid:443"; })
    (baseSettings // { domain = "site.example.invalid."; })
    (baseSettings // { publicIPv4 = "192.0.2.999"; })
    (baseSettings // { bindIPv4 = "0.0.0.0"; })
    (baseSettings // { bindIPv4 = "listener.example.invalid"; })
    (baseSettings // { passwordSecretNames = { }; })
    (
      baseSettings
      // {
        passwordSecretNames = {
          "bad identity" = "fixture/one";
          laptop = "fixture/two";
        };
      }
    )
    (
      baseSettings
      // {
        passwordSecretNames = {
          phone = "fixture/../secret";
          laptop = "fixture/two";
        };
      }
    )
    (
      baseSettings
      // {
        passwordSecretNames = {
          phone = "fixture/shared";
          laptop = "fixture/shared";
        };
      }
    )
    (baseSettings // { additionalDeny = [ "127.0.0.1\nallow all" ]; })
    (baseSettings // { additionalDeny = [ "admin.example.invalid" ]; })
    (baseSettings // { additionalDeny = [ "01.2.3.4" ]; })
    (baseSettings // { additionalDeny = [ "999999999999999999999.2.3.4" ]; })
    (baseSettings // { additionalDeny = [ "2001:db8:::1/128" ]; })
  ];
  schemaContract =
    builtins.deepSeq schemaResults (builtins.all (value: value) schemaResults)
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
    );
  selected = baseline.machine.services.caddy.virtualHosts.${baseSettings.domain};
  inherit (baseline) route template;
  routePosition =
    text: builtins.stringLength (builtins.head (lib.splitString text selected.extraConfig));
  fragmentCopies =
    fragment: text:
    builtins.length (lib.splitString (builtins.unsafeDiscardStringContext fragment) text) - 1;
  coverHost = baseline.machine.services.caddy.virtualHosts."cover.example.invalid";
  coverPosition =
    text: builtins.stringLength (builtins.head (lib.splitString text coverHost.extraConfig));
  routeContract =
    lib.hasPrefix "route {\n" route
    && lib.hasInfix "method CONNECT" route
    && lib.hasInfix ''{http.request.local.host} == "192.0.2.10"'' route
    && lib.hasInfix "{http.request.local.port} == 443" route
    && !(lib.hasInfix ''{http.request.local.port} == "443"'' route)
    && !(lib.hasInfix "198.51.100.77" route)
    && lib.hasInfix "import ${template.path}" route
    && selected.hostName == ":443"
    && selected.forwardProxy
    && selected.listenAddresses == [ "192.0.2.10" ]
    && selected.owner == "fixture:site"
    && selected.useACMEHost == "fixture"
    && selected.serverAliases == [ "site-alias.example.invalid" ]
    && fragmentCopies route selected.extraConfig == 1
    && routePosition route < routePosition "@fixture_site_alias"
    && routePosition "@fixture_site_alias" < routePosition "# fixture-terminal-fallback"
    &&
      builtins.all
        (
          domain:
          let
            host = baseline.machine.services.caddy.virtualHosts.${domain};
          in
          !(lib.hasInfix "method CONNECT" host.extraConfig)
          && !host.forwardProxy
          && host.hostName == domain
          && lib.hasInfix ''respond "cover"'' host.extraConfig
        )
        [
          "private.example.invalid"
          "disjoint.example.invalid"
        ]
    && coverHost.owner == "fixture:cover.example.invalid"
    && coverHost.hostName == "cover.example.invalid"
    && coverHost.serverAliases == [ "cover-alias.example.invalid" ]
    && coverHost.useACMEHost == "fixture"
    && !coverHost.forwardProxy
    && fragmentCopies route coverHost.extraConfig == 1
    && coverPosition route < coverPosition "@cover_alias"
    && coverPosition "@cover_alias" < coverPosition "# cover-terminal-content"
    && lib.hasInfix ''respond "cover"'' coverHost.extraConfig
    &&
      baseline.machine.services.caddy.virtualHosts."private.example.invalid".listenAddresses
      == [ "100.64.0.10" ]
    &&
      baseline.machine.services.caddy.virtualHosts."disjoint.example.invalid".listenAddresses
      == [ "192.0.2.20" ]
    &&
      baseline.machine.services.caddy.virtualHosts."cover.example.invalid".listenAddresses
      == [ "192.0.2.10" ]
    && !(lib.hasInfix "method CONNECT"
      baseline.machine.services.caddy.virtualHosts."unattached.example.invalid".extraConfig
    )
    && lib.hasInfix "persist_config off" baseline.machine.services.caddy.globalConfig;
  authContract =
    template.owner == "root"
    && template.group == "caddy"
    && template.mode == "0440"
    && template.reloadUnits == [ "caddy.service" ]
    && lib.hasPrefix "forward_proxy {" template.content
    && lib.hasInfix "basic_auth bsv ${baseline.machine.sops.placeholder."fixture/naive-second-password"}" template.content
    && lib.hasInfix "basic_auth ibelyasov ${baseline.machine.sops.placeholder."fixture/naive-first-password"}" template.content
    && lib.hasInfix "deny 0.0.0.0/8" template.content
    && lib.hasInfix "203.0.113.77/32" template.content
    && lib.hasInfix "100:0:0:1::/64" template.content
    && lib.hasInfix "2001:2::/48" template.content
    && lib.hasInfix "3fff::/20" template.content
    && lib.hasInfix "5f00::/16" template.content
    && lib.hasInfix "allow all" template.content
    && !(lib.hasInfix "ports 80 443" template.content)
    && lib.hasInfix "probe_resistance" template.content
    && lib.hasInfix "hide_ip" template.content
    && lib.hasInfix "hide_via" template.content
    && builtins.all (
      name:
      let
        secret = baseline.machine.sops.secrets.${name};
      in
      secret.owner == "root"
      && secret.group == "root"
      && secret.mode == "0400"
      && secret.restartUnits == [ ]
      && secret.reloadUnits == [ ]
    ) (builtins.attrValues baseSettings.passwordSecretNames);
  dependencyContract =
    builtins.elem "sops-install-secrets.service" baseline.machine.systemd.services.caddy.after
    && builtins.elem "sops-install-secrets.service" baseline.machine.systemd.services.caddy.wants
    && !(builtins.elem "sops-install-secrets.service" baseline.machine.systemd.services.caddy.requires)
    && !(builtins.elem "sops-install-secrets.service" activationScriptMode.machine.systemd.services.caddy.after)
    && !(builtins.elem "sops-install-secrets.service" activationScriptMode.machine.systemd.services.caddy.wants);
  contextArtifact = pkgs.writeText "naiveproxy-route-context-fixture" "synthetic context only";
  expectedContext = builtins.getContext "${contextArtifact}";
  contextual = evaluate {
    extraModule.sops.templates.${templateName}.path = lib.mkForce "${contextArtifact}/naiveproxy.caddy";
  };
  contextResults = {
    owned = contextual.assertionsPass;
    native = contextual.nativeAssertionsPass;
    expectedNonempty = expectedContext != { };
    exported =
      builtins.intersectAttrs expectedContext (builtins.getContext contextual.route) == expectedContext;
    attached =
      builtins.intersectAttrs expectedContext (
        builtins.getContext
          contextual.machine.services.caddy.virtualHosts.${baseSettings.domain}.extraConfig
      ) == expectedContext;
    coverAttached =
      builtins.intersectAttrs expectedContext (
        builtins.getContext
          contextual.machine.services.caddy.virtualHosts."cover.example.invalid".extraConfig
      ) == expectedContext;
    rootOnce =
      fragmentCopies contextual.route
        contextual.machine.services.caddy.virtualHosts.${baseSettings.domain}.extraConfig == 1;
    coverOnce =
      fragmentCopies contextual.route
        contextual.machine.services.caddy.virtualHosts."cover.example.invalid".extraConfig == 1;
  };
  contextContract = builtins.deepSeq contextResults (
    builtins.all (value: value) (builtins.attrValues contextResults)
  );
  failedDiagnostics =
    result:
    map (entry: entry.message) (builtins.filter (entry: !entry.assertion) result.machine.assertions);
  diagnostics = {
    inherit
      compositionResults
      contextResults
      overrideResults
      expectedContext
      ;
    baselineActiveInstances = baseline.machine.clanwright.vpn.naiveproxy.activeInstances;
    activeDisabledInstances = activeWithDisabled.machine.clanwright.vpn.naiveproxy.activeInstances;
    dualActiveInstances = twoActive.machine.clanwright.vpn.naiveproxy.activeInstances;
    baselineClaimDefinitions = baseline.activeInstanceDefinitions;
    activeDisabledClaimDefinitions = activeWithDisabled.activeInstanceDefinitions;
    baselineFailures = failedDiagnostics baseline;
    activationFailures = failedDiagnostics activationScriptMode;
    arbitraryFailures = failedDiagnostics arbitrary;
    usersOnlyFailures = failedDiagnostics usersOnly;
    activeDisabledFailures = failedDiagnostics activeWithDisabled;
    contextFailures = failedDiagnostics contextual;
    pathContext = builtins.getContext contextual.template.path;
    exportedContext = builtins.getContext contextual.route;
    attachedContext =
      builtins.getContext
        contextual.machine.services.caddy.virtualHosts.${baseSettings.domain}.extraConfig;
  };
  results = {
    inherit
      compositionContract
      disabledContract
      exportContract
      schemaContract
      routeContract
      authContract
      dependencyContract
      contextContract
      ;
  };
  contract = builtins.deepSeq results (builtins.all (value: value) (builtins.attrValues results));
in
if !contract then
  throw "NaiveProxy native contract failed: ${builtins.toJSON { inherit results diagnostics; }}"
else
  results
  // {
    all = true;
    inherit contract;
  }
