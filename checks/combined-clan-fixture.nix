{
  combined,
  dataMesherSource,
  fixture,
  lib,
  publisherManifest,
}:
let
  supportNames = [
    "network-caddy"
    "network-certificates"
  ];
  serviceNames = builtins.filter (name: !(builtins.elem name supportNames)) (
    builtins.attrNames fixture.instances
  );
  inherit (combined) config machine;
  machineOptions = config.nixosConfigurations.vpn-fixture.options;
  publisherFieldOptions =
    machineOptions.clanwright.vpn.publishers.type.nestedTypes.elemType.getSubOptions
      [ ];
  units = machine.systemd.services;
  adguardTemplateNames = builtins.filter (lib.hasSuffix "-adguardhome.yaml") (
    builtins.attrNames machine.sops.templates
  );
  adguardTemplate = machine.sops.templates.${builtins.head adguardTemplateNames};
  adguardSettings = builtins.fromJSON adguardTemplate.content;
  adguardIntegration = machine.clanwright.dns.adguardhome.integration;
  publisherIntegration = machine.clanwright.vpn.publishers.vpn-client-profiles;
  expectedPublicationPhaseIds = [
    "revoke-current"
    "sync-local-assets"
    "check-assets"
    "prepare-generation"
    "render-artifacts"
    "finalize-links"
    "seal-generation"
    "expose-generation"
    "retire-old-generations"
    "cleanup-private-temporaries"
  ];
  caddySites = machine.services.caddy.virtualHosts;
  acmeReloadUnits = machine.security.acme.certs.fixture.reloadServices;
  publicationUnitName = lib.removeSuffix ".service" publisherIntegration.publicationUnit;
  refreshUnitName = lib.removeSuffix ".service" publisherIntegration.refreshUnit;
  publicationUnit = units.${publicationUnitName};
  refreshUnit = units.${refreshUnitName};
  publicationPhaseMarker = "# publication-phase:";
  publicationScriptPhaseRegions = builtins.tail (
    lib.splitString publicationPhaseMarker publicationUnit.script
  );
  phaseIdsFor =
    script:
    map (segment: builtins.head (lib.splitString "\n" segment)) (
      builtins.tail (lib.splitString publicationPhaseMarker script)
    );
  publicationScriptPhaseIds = phaseIdsFor publicationUnit.script;
  phaseRegion =
    id:
    builtins.head (
      builtins.filter (
        segment: builtins.head (lib.splitString "\n" segment) == id
      ) publicationScriptPhaseRegions
    );
  revokeCommand = "rm -f -- ${publisherIntegration.profileRoot}";
  generationsFind = ''find "$runtime_base/generations"'';
  revokePhaseRegion = builtins.head publicationScriptPhaseRegions;
  revokeRegionBeforeGenerationsFind = builtins.head (
    lib.splitString generationsFind revokePhaseRegion
  );
  caddyUnit = units.caddy;
  mieruPasswordSecret = machine.sops.secrets."fixture-mieru-password";
  anytlsPasswordSecret = machine.sops.secrets."fixture-anytls-password";
  trustTunnelPasswordSecret = machine.sops.secrets."fixture-trusttunnel-password";
  pathTokenSecret = machine.sops.secrets."publisher-profile-path-token-cHJvYmU";
  tmpfilesRules = machine.systemd.tmpfiles.rules;
  nativeDataMesherResults = {
    nativeEnableDeclaration =
      machineOptions.services.data-mesher.enable.declarations == [
        (dataMesherSource + "/nix/nixosModules/data-mesher/module.nix")
      ];
    disabledByNativeDefault =
      machineOptions.services.data-mesher.enable.default == false
      && machine.services.data-mesher.enable == false;
    noServiceOrUnit = !(units ? data-mesher) && !(machine.systemd.units ? "data-mesher.service");
    noIdentity = !(machine.users.users ? data-mesher) && !(machine.users.groups ? data-mesher);
    noConfiguration = !(machine.environment.etc ? "data-mesher/dm.toml");
    noRuntimeTmpfiles = builtins.all (rule: !(lib.hasInfix "data-mesher" rule)) tmpfilesRules;
    noSystemPackage = builtins.all (
      package: lib.getName package != "data-mesher"
    ) machine.environment.systemPackages;
  };
  afterFinalPrivateReset = lib.last (lib.splitString "private_tmp_files=()" publicationUnit.script);
  afterLocalAssetSync = lib.last (lib.splitString "local_asset_tmp=" publicationUnit.script);
  requiredFixtureAssetNames = map (asset: asset.filename) (
    builtins.attrValues publisherManifest.assetCatalog
  );
  refreshPreservesCache =
    !(lib.hasInfix "rm -f ${publisherIntegration.assetRoot}/" refreshUnit.script)
    && lib.hasInfix ''publish_file "$tmp" "$name"'' refreshUnit.script
    && lib.hasInfix ''record_status "$name" failed download_failed'' refreshUnit.script;
  publisherChecksCompleteAssetsAfterRefresh =
    builtins.elem publisherIntegration.refreshUnit (lib.toList publicationUnit.after)
    && builtins.elem publisherIntegration.refreshUnit (lib.toList publicationUnit.wants)
    && !(builtins.elem publisherIntegration.refreshUnit (lib.toList (publicationUnit.requires or [ ])))
    && builtins.all (
      name: lib.hasInfix "test -s ${publisherIntegration.assetRoot}/${name}" afterLocalAssetSync
    ) requiredFixtureAssetNames
    && !(lib.hasInfix "segments.txt" refreshUnit.script);
  publicationPhaseResults = {
    manifestContainsBothClientFormats =
      map (profile: profile.name) publisherManifest.profiles == [ "cHJvYmU" ]
      &&
        map (artifact: artifact.outputName) (builtins.head publisherManifest.profiles).artifacts == [
          "mihomo.yaml"
          "profile.json"
        ];
    actualPublicationUsesManifestTemplates = builtins.all (
      profile:
      builtins.all (
        artifact:
        lib.hasInfix (builtins.unsafeDiscardStringContext (toString artifact.templatePath)) publicationUnit.script
      ) profile.artifacts
    ) publisherManifest.profiles;
    actualPublicationUsesManifestBindings = builtins.all (
      profile:
      builtins.all (
        artifact:
        builtins.all (
          binding:
          lib.hasInfix machine.sops.secrets.${binding.secretName}.path publicationUnit.script
          &&
            builtins.elem publisherIntegration.publicationUnit
              machine.sops.secrets.${binding.secretName}.restartUnits
        ) artifact.bindings
      ) profile.artifacts
    ) publisherManifest.profiles;
    scriptHasExactTenOrderedPhases = publicationScriptPhaseIds == expectedPublicationPhaseIds;
    removedManifestGraph =
      builtins.attrNames publisherManifest == [
        "assetCatalog"
        "profiles"
        "schemaVersion"
      ]
      && builtins.all (field: !(builtins.hasAttr field machine.clanwright.vpn)) [
        "publisherPublicationPhases"
        "publisherManifests"
        "publisherRenders"
      ];
    swappedMarkersDetected =
      phaseIdsFor (
        builtins.replaceStrings
          [
            "# publication-phase:render-artifacts"
            "# publication-phase:expose-generation"
          ]
          [
            "# publication-phase:expose-generation"
            "# publication-phase:render-artifacts"
          ]
          publicationUnit.script
      ) != expectedPublicationPhaseIds;
    missingMarkerDetected =
      phaseIdsFor (
        builtins.replaceStrings
          [
            "# publication-phase:seal-generation"
          ]
          [ "# removed-phase" ]
          publicationUnit.script
      ) != expectedPublicationPhaseIds;
    duplicateMarkerDetected =
      phaseIdsFor (publicationUnit.script + "\n# publication-phase:expose-generation\n")
      != expectedPublicationPhaseIds;
    revokePhaseRemovesCurrentBeforeGenerationCleanup =
      lib.hasInfix generationsFind revokePhaseRegion
      && lib.hasInfix revokeCommand revokeRegionBeforeGenerationsFind;
    assetPreparationBeforeGeneration =
      lib.hasInfix "local_asset_tmp=" (phaseRegion "sync-local-assets")
      && builtins.all (
        name: lib.hasInfix "test -s ${publisherIntegration.assetRoot}/${name}" (phaseRegion "check-assets")
      ) requiredFixtureAssetNames
      && lib.hasInfix ''stage="$(mktemp -d'' (phaseRegion "prepare-generation");
    renderingBeforeSealedExposure =
      lib.hasInfix "--rawfile binding_" (phaseRegion "render-artifacts")
      && lib.hasInfix ''find "$stage" -type f -exec chmod 0440'' (phaseRegion "seal-generation")
      && lib.hasInfix ''mv -- "$stage" "$generation"'' (phaseRegion "seal-generation")
      && lib.hasInfix ''ln -s -- "$generation" "$link_tmp"'' (phaseRegion "expose-generation")
      && lib.hasInfix ''mv -Tf -- "$link_tmp"'' (phaseRegion "expose-generation");
    retirementAndPrivateCleanupAfterExposure =
      lib.hasInfix ''! -path "$generation" -exec rm -rf'' (phaseRegion "retire-old-generations")
      && lib.hasInfix ''rm -f -- "''${private_tmp_files[@]}"'' (phaseRegion "cleanup-private-temporaries")
      && lib.hasInfix "private_tmp_files=()" (phaseRegion "cleanup-private-temporaries")
      && lib.hasInfix "trap - EXIT" (phaseRegion "cleanup-private-temporaries");
  };
  publicationPhaseContract = builtins.all (value: value) (
    builtins.attrValues publicationPhaseResults
  );
  assetLifecycleResults = {
    emptyDirectoryGuardPresent =
      publisherChecksCompleteAssetsAfterRefresh && lib.hasInfix "exit \"$missing\"" refreshUnit.script;
    unavailableSourceWithoutCacheFailsClosed =
      publisherChecksCompleteAssetsAfterRefresh
      && lib.hasInfix ''record_status "$name" failed download_failed'' refreshUnit.script;
    unavailableSourceWithCompleteCachePublishes =
      refreshPreservesCache && publisherChecksCompleteAssetsAfterRefresh;
    retryDeclarationsPresent =
      refreshUnit.serviceConfig.Restart == "on-failure"
      && publicationUnit.serviceConfig.Restart == "on-failure";
  };
  unitDoesNotReference =
    referenced: unit:
    builtins.all (field: !(builtins.elem referenced (lib.toList (unit.${field} or [ ])))) [
      "after"
      "before"
      "requires"
      "requiredBy"
      "wants"
      "wantedBy"
    ];
  nativeCompositionResults = import ./lib/native-composition.nix { inherit lib; } {
    inherit machine publisherManifest;
    domain = "profiles.example.invalid";
  };
  contract =
    builtins.attrNames config.inventory.instances
    == lib.sort builtins.lessThan (supportNames ++ serviceNames)
    && builtins.length (builtins.attrNames config._services.allServices) == 11
    && builtins.all (value: value) (builtins.attrValues nativeCompositionResults)
    && builtins.all (value: value) (builtins.attrValues nativeDataMesherResults)
    && machine.services.xray.enable
    && units ? xray
    && units ? mita
    && machine.sops.templates ? "mita.json"
    && machine.sops.templates."mita.json".owner == "mita"
    && machine.sops.templates."mita.json".group == "mita"
    && machine.sops.templates."mita.json".mode == "0400"
    && machine.sops.templates."mita.json".restartUnits == [ "mita.service" ]
    && mieruPasswordSecret.owner == "root"
    && mieruPasswordSecret.group == "root"
    && mieruPasswordSecret.mode == "0400"
    &&
      lib.sort builtins.lessThan mieruPasswordSecret.restartUnits == lib.sort builtins.lessThan [
        "mita.service"
        publisherIntegration.publicationUnit
      ]
    && units ? trusttunnel
    && machine.sops.templates ? "trusttunnel.toml"
    && machine.sops.templates."trusttunnel.toml".owner == "trusttunnel"
    && machine.sops.templates."trusttunnel.toml".group == "trusttunnel"
    && machine.sops.templates."trusttunnel.toml".mode == "0400"
    && machine.sops.templates."trusttunnel.toml".restartUnits == [ "trusttunnel.service" ]
    && trustTunnelPasswordSecret.owner == "root"
    && trustTunnelPasswordSecret.group == "root"
    && trustTunnelPasswordSecret.mode == "0400"
    &&
      lib.sort builtins.lessThan trustTunnelPasswordSecret.restartUnits == lib.sort builtins.lessThan [
        "trusttunnel.service"
        publisherIntegration.publicationUnit
      ]
    && machine.services.sing-box.enable
    && units ? sing-box
    && !(units ? anytls)
    && !(machine.sops.templates ? "anytls.json")
    && machine.systemd.services.sing-box.serviceConfig.User == "sing-box"
    && machine.systemd.services.sing-box.serviceConfig.Group == "sing-box"
    &&
      (builtins.head (builtins.head machine.services.sing-box.settings.inbounds).users).password == {
        _secret = "/run/credentials/sing-box.service/password-cHJvYmU";
      }
    && builtins.elem "password-cHJvYmU:${anytlsPasswordSecret.path}" machine.systemd.services.sing-box.serviceConfig.LoadCredential
    && anytlsPasswordSecret.owner == "root"
    && anytlsPasswordSecret.group == "root"
    && anytlsPasswordSecret.mode == "0400"
    &&
      lib.sort builtins.lessThan anytlsPasswordSecret.restartUnits == lib.sort builtins.lessThan [
        "sing-box.service"
        publisherIntegration.publicationUnit
      ]
    && !((machine.networkCore.mihomo or { }) ? vlessXhttp)
    && !(units ? mihomo-gateway)
    && machine.sops.templates ? "naiveproxy-vpn-fixture.caddy"
    && machine.sops.templates."naiveproxy-vpn-fixture.caddy".reloadUnits == [ "caddy.service" ]
    && !(units ? naiveproxy-caddy-fragment-fixture)
    && !(units ? naiveproxy-caddy-refresh-fixture)
    && machine.services.adguardhome.enable
    && machine.services.adguardhome.settings == null
    && machine.services.dnsproxy.enable
    && builtins.length adguardTemplateNames == 1
    && adguardTemplate.restartUnits == [ "adguardhome.service" ]
    && machine.services.unbound.enable
    && builtins.elem "unbound.service" units.adguardhome.wants
    && !(builtins.elem "unbound.service" units.adguardhome.after)
    && !(builtins.elem "unbound.service" units.adguardhome.requires)
    && adguardSettings.dns.upstream_dns == [ "127.0.0.1:5335" ]
    && adguardSettings.dns.fallback_dns == [ "127.0.0.1:5336" ]
    &&
      adguardIntegration == {
        schemaVersion = 1;
        uiBackend = {
          host = "127.0.0.1";
          port = 3000;
        };
        dohBackend = {
          host = "127.0.0.1";
          port = 8444;
          serverName = "dns.example.invalid";
        };
        reloadUnits = [ "adguardhome.service" ];
      }
    && machineOptions.clanwright.dns.adguardhome.integration.readOnly
    && caddySites ? "adguard.example.invalid"
    && caddySites."adguard.example.invalid".listenAddresses == [ "100.64.0.10" ]
    &&
      lib.hasInfix ''{http.request.local.host} != "100.64.0.10"''
        caddySites."adguard.example.invalid".extraConfig
    && lib.hasInfix "{http.request.local.port} != 443" caddySites."adguard.example.invalid".extraConfig
    && caddySites ? "dns.example.invalid"
    && caddySites."dns.example.invalid".listenAddresses == [ "192.0.2.10" ]
    &&
      lib.hasInfix ''{http.request.local.host} != "192.0.2.10"''
        caddySites."dns.example.invalid".extraConfig
    &&
      lib.hasInfix "tls_server_name ${adguardIntegration.dohBackend.serverName}"
        caddySites."dns.example.invalid".extraConfig
    && builtins.elem "caddy.service" acmeReloadUnits
    && builtins.elem "adguardhome.service" acmeReloadUnits
    && builtins.elem "acme" (lib.toList units.adguardhome.serviceConfig.SupplementaryGroups)
    &&
      machine.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [
        53
        443
      ]
    && machine.networking.firewall.interfaces.tailscale0.allowedUDPPorts == [ 53 ]
    && publisherIntegration.schemaVersion == 2
    && publisherFieldOptions.schemaVersion.type.check 2
    && !(publisherFieldOptions.schemaVersion.type.check 1)
    && builtins.all (field: publisherFieldOptions.${field}.readOnly) [
      "schemaVersion"
      "configGatewayDomain"
      "profileRoot"
      "assetRoot"
      "linksRoot"
      "logConfig"
      "routeConfig"
      "publicationUnit"
      "refreshUnit"
      "statusPath"
      "readerGroup"
    ]
    && publisherIntegration.profileRoot == "/run/vpn-client-profiles/fixture/published/current"
    && publisherIntegration.configGatewayDomain == "profiles.example.invalid"
    && publisherIntegration.assetRoot == "/var/lib/vpn-client-profiles/fixture/assets"
    && publisherIntegration.linksRoot == "/run/vpn-client-profiles/fixture/published/current/links"
    && publisherIntegration.statusPath == "/var/lib/vpn-client-profiles/fixture/status.json"
    && publisherIntegration.readerGroup == "vpn-client-profiles"
    && publisherIntegration.publicationUnit == "vpn-client-profiles-publish-fixture.service"
    && publisherIntegration.refreshUnit == "vpn-client-profiles-public-assets-fixture.service"
    && lib.hasInfix "log_skip" publisherIntegration.logConfig
    && lib.hasPrefix "route {" (lib.strings.trim publisherIntegration.routeConfig)
    && lib.hasInfix "profiles.example.invalid" publisherIntegration.routeConfig
    && !(lib.hasInfix "bind " publisherIntegration.routeConfig)
    && !(lib.hasInfix "tls " publisherIntegration.routeConfig)
    && !(lib.hasInfix "import " publisherIntegration.routeConfig)
    && builtins.all (
      asset: lib.hasInfix "handle ${asset.publicPath}" publisherIntegration.routeConfig
    ) (builtins.attrValues publisherManifest.assetCatalog)
    && caddySites ? "profiles.example.invalid"
    && caddySites."profiles.example.invalid".hostName == publisherIntegration.configGatewayDomain
    &&
      caddySites."profiles.example.invalid".listenAddresses == [
        "192.0.2.10"
        "100.64.0.10"
      ]
    &&
      lib.hasInfix ''{http.request.local.host} != "100.64.0.10"''
        caddySites."profiles.example.invalid".extraConfig
    && lib.hasInfix publisherIntegration.linksRoot caddySites."profiles.example.invalid".extraConfig
    &&
      lib.hasInfix (builtins.unsafeDiscardStringContext publisherIntegration.routeConfig)
        caddySites."profiles.example.invalid".extraConfig
    && lib.hasInfix publisherIntegration.logConfig caddySites."profiles.example.invalid".extraConfig
    && builtins.elem publisherIntegration.readerGroup (
      lib.toList caddyUnit.serviceConfig.SupplementaryGroups
    )
    && unitDoesNotReference publisherIntegration.publicationUnit caddyUnit
    && unitDoesNotReference "caddy.service" publicationUnit
    && publicationUnit.serviceConfig.Restart == "on-failure"
    && lib.hasSuffix "/bin/rm -f ${publisherIntegration.profileRoot}" publicationUnit.serviceConfig.ExecStartPre
    && lib.hasInfix "rm -f -- ${publisherIntegration.profileRoot}" publicationUnit.postStop
    && lib.hasInfix "find /run/vpn-client-profiles/fixture/generations" publicationUnit.postStop
    && lib.hasInfix "/bin/rm -rf -- {} +" publicationUnit.postStop
    && lib.hasInfix "exec >/dev/null 2>&1" publicationUnit.postStop
    && lib.hasInfix ''mv -Tf -- "$link_tmp" ${publisherIntegration.profileRoot}'' publicationUnit.script
    && builtins.all (rule: builtins.elem rule tmpfilesRules) [
      "d /run/vpn-client-profiles/fixture 0750 root ${publisherIntegration.readerGroup} -"
      "d /run/vpn-client-profiles/fixture/published 0750 root ${publisherIntegration.readerGroup} -"
      "d /run/vpn-client-profiles/fixture/generations 0750 root ${publisherIntegration.readerGroup} -"
    ]
    && lib.hasInfix ''find "$stage" -type d -exec chmod 0750'' publicationUnit.script
    && lib.hasInfix ''find "$stage" -type f -exec chmod 0440'' publicationUnit.script
    && lib.hasInfix ''private_tmp_files+=("$tmp")'' publicationUnit.script
    && lib.hasInfix ''rm -f -- "''${private_tmp_files[@]}"'' publicationUnit.script
    && lib.hasInfix "trap - EXIT" afterFinalPrivateReset
    && lib.hasInfix "test -s ${publisherIntegration.assetRoot}/" publicationUnit.script
    && builtins.elem publisherIntegration.refreshUnit (lib.toList publicationUnit.after)
    && builtins.elem publisherIntegration.refreshUnit (lib.toList publicationUnit.wants)
    && !(builtins.elem publisherIntegration.refreshUnit (lib.toList (publicationUnit.requires or [ ])))
    && lib.hasInfix "failure_stage=assets-readiness" publicationUnit.script
    && lib.hasInfix "failure_reason=required-assets-missing-or-empty" publicationUnit.script
    && publicationPhaseContract
    && publisherChecksCompleteAssetsAfterRefresh
    && builtins.all (value: value) (builtins.attrValues assetLifecycleResults)
    && refreshUnit.serviceConfig.Restart == "on-failure"
    && machine.systemd.timers.${refreshUnitName}.timerConfig.Persistent
    && lib.hasInfix ''record_status "$name" failed download_failed'' refreshUnit.script
    && lib.hasInfix "main/wildcard/doh-onlydomains.txt" refreshUnit.script
    && !(lib.hasInfix "main/domains/doh.txt" refreshUnit.script)
    && lib.hasInfix "main/adblock/doh.txt" refreshUnit.script
    && refreshPreservesCache
    && lib.hasInfix publisherIntegration.statusPath refreshUnit.script
    && pathTokenSecret.restartUnits == [ publisherIntegration.publicationUnit ]
    && lib.hasInfix pathTokenSecret.path publicationUnit.script
    && machine.services.dnsproxy.settings.listen-addrs == [ "127.0.0.1" ]
    && caddySites ? "site.example.invalid"
    && caddySites."site.example.invalid".forwardProxy
    && caddySites."site.example.invalid".hostName == ":443";
in
if !contract then
  throw "Combined external Clan fixture contract failed: ${
    builtins.toJSON {
      inherit publicationPhaseResults nativeCompositionResults nativeDataMesherResults;
    }
  }"
else
  {
    all = true;
    inherit
      nativeCompositionResults
      nativeDataMesherResults
      assetLifecycleResults
      contract
      publicationPhaseContract
      publicationPhaseResults
      ;
  }
