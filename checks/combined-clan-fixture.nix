{
  combined,
  fixture,
  lib,
}:
let
  supportNames = [
    "edge-wildcard-certificate"
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
  publisherManifest = machine.clanwright.vpn.publisherManifests.vpn-client-profiles;
  inherit (publisherManifest) publicationPhases;
  publicationPhaseIds = map (phase: phase.id) publicationPhases;
  indexOf =
    predicate: values:
    let
      go =
        index: remaining:
        if remaining == [ ] || predicate (builtins.head remaining) then
          index
        else
          go (index + 1) (builtins.tail remaining);
    in
    go 0 values;
  phaseIndex = id: indexOf (candidate: candidate == id) publicationPhaseIds;
  phasePrerequisites =
    id: (builtins.head (builtins.filter (phase: phase.id == id) publicationPhases)).prerequisites;
  caddyFragments = machine.networkCore.caddy.effectiveFragments;
  acmeReloadUnits = machine.networkCore.acme.reloadServices.fixture;
  publicationUnitName = lib.removeSuffix ".service" publisherIntegration.publicationUnit;
  refreshUnitName = lib.removeSuffix ".service" publisherIntegration.refreshUnit;
  publicationUnit = units.${publicationUnitName};
  refreshUnit = units.${refreshUnitName};
  publicationPhaseMarker = "# publication-phase:";
  publicationScriptPhaseRegions = builtins.tail (
    lib.splitString publicationPhaseMarker publicationUnit.script
  );
  publicationScriptPhaseIds = map (
    segment: builtins.head (lib.splitString "\n" segment)
  ) publicationScriptPhaseRegions;
  revokeCommand = "rm -f -- ${publisherIntegration.profileRoot}";
  generationsFind = ''find "$runtime_base/generations"'';
  revokePhaseRegion = builtins.head publicationScriptPhaseRegions;
  revokeRegionBeforeGenerationsFind = builtins.head (
    lib.splitString generationsFind revokePhaseRegion
  );
  caddyUnit = units.caddy;
  mieruPasswordSecret = machine.sops.secrets."fixture-mieru-password";
  anytlsPasswordSecret = machine.sops.secrets."fixture-anytls-password";
  pathTokenSecret = machine.sops.secrets."mihomo-client-fixture-cHJvYmU-path-token";
  tmpfilesRules = machine.systemd.tmpfiles.rules;
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
    revokePrecedesAssetPreparation =
      phasePrerequisites "sync-local-assets" == [ "revoke-current" ]
      && phaseIndex "revoke-current" < phaseIndex "sync-local-assets";
    assetsPrecedeGeneration =
      phasePrerequisites "check-assets" == [ "sync-local-assets" ]
      && phasePrerequisites "prepare-generation" == [ "check-assets" ]
      && phaseIndex "check-assets" < phaseIndex "prepare-generation";
    renderPrecedesExposure =
      phasePrerequisites "render-artifacts" == [ "prepare-generation" ]
      && phasePrerequisites "expose-generation" == [ "seal-generation" ]
      && phaseIndex "render-artifacts" < phaseIndex "expose-generation";
    retirementAndCleanupFollowExposure =
      phasePrerequisites "retire-old-generations" == [ "expose-generation" ]
      && phasePrerequisites "cleanup-private-temporaries" == [ "retire-old-generations" ]
      && phaseIndex "expose-generation" < phaseIndex "cleanup-private-temporaries";
    scriptMarkersMatchManifestOrder = publicationScriptPhaseIds == publicationPhaseIds;
    revokePhaseRemovesCurrentBeforeGenerationCleanup =
      lib.hasInfix generationsFind revokePhaseRegion
      && lib.hasInfix revokeCommand revokeRegionBeforeGenerationsFind;
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
  contract =
    builtins.attrNames config.inventory.instances
    == lib.sort builtins.lessThan (supportNames ++ serviceNames)
    && builtins.length (builtins.attrNames config._services.allServices) == 12
    && machine.services.xray.enable
    && units ? xray
    && units ? mihomo-hysteria2
    && machine.sops.templates ? "mihomo-hysteria2.json"
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
    && units ? anytls
    && machine.sops.templates ? "anytls.json"
    && machine.sops.templates."anytls.json".owner == "anytls"
    && machine.sops.templates."anytls.json".group == "anytls"
    && machine.sops.templates."anytls.json".mode == "0400"
    && machine.sops.templates."anytls.json".restartUnits == [ "anytls.service" ]
    && anytlsPasswordSecret.owner == "root"
    && anytlsPasswordSecret.group == "root"
    && anytlsPasswordSecret.mode == "0400"
    &&
      lib.sort builtins.lessThan anytlsPasswordSecret.restartUnits == lib.sort builtins.lessThan [
        "anytls.service"
        publisherIntegration.publicationUnit
      ]
    && !((machine.networkCore.mihomo or { }) ? vlessXhttp)
    && !((machine.networkCore.mihomo or { }) ? hysteria2)
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
    && caddyFragments ? dns-adguardhome-ui
    && caddyFragments.dns-adguardhome-ui.listenAddresses == [ "100.64.0.10" ]
    && lib.hasInfix ''{http.request.local.host} != "100.64.0.10"'' caddyFragments.dns-adguardhome-ui.extraConfig
    && lib.hasInfix ''{http.request.local.port} != "443"'' caddyFragments.dns-adguardhome-ui.extraConfig
    && caddyFragments ? dns-adguardhome-doh
    && caddyFragments.dns-adguardhome-doh.listenAddresses == [ "192.0.2.10" ]
    && lib.hasInfix ''{http.request.local.host} != "192.0.2.10"'' caddyFragments.dns-adguardhome-doh.extraConfig
    && lib.hasInfix "tls_server_name ${adguardIntegration.dohBackend.serverName}" caddyFragments.dns-adguardhome-doh.extraConfig
    && builtins.elem "caddy.service" acmeReloadUnits
    && builtins.elem "adguardhome.service" acmeReloadUnits
    && builtins.elem "acme" (lib.toList units.adguardhome.serviceConfig.SupplementaryGroups)
    &&
      machine.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [
        53
        443
      ]
    && machine.networking.firewall.interfaces.tailscale0.allowedUDPPorts == [ 53 ]
    && publisherIntegration.schemaVersion == 1
    && publisherFieldOptions.schemaVersion.type.check 1
    && !(publisherFieldOptions.schemaVersion.type.check 2)
    && builtins.all (field: publisherFieldOptions.${field}.readOnly) [
      "schemaVersion"
      "configGatewayDomain"
      "profileRoot"
      "assetRoot"
      "linksRoot"
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
    && lib.hasPrefix "log_skip" (lib.strings.trim publisherIntegration.routeConfig)
    && !(lib.hasInfix "profiles.example.invalid" publisherIntegration.routeConfig)
    && !(lib.hasInfix "bind " publisherIntegration.routeConfig)
    && !(lib.hasInfix "tls " publisherIntegration.routeConfig)
    && !(lib.hasInfix "import " publisherIntegration.routeConfig)
    && builtins.all (
      asset: lib.hasInfix "handle ${asset.publicPath}" publisherIntegration.routeConfig
    ) (builtins.attrValues publisherManifest.assetCatalog)
    && machine.clanwright.vpn.publisherPublicationPhases.vpn-client-profiles == publicationPhases
    && caddyFragments ? vpn-client-profiles
    && caddyFragments.vpn-client-profiles.hostName == publisherIntegration.configGatewayDomain
    &&
      caddyFragments.vpn-client-profiles.listenAddresses == [
        "192.0.2.10"
        "100.64.0.10"
      ]
    && lib.hasInfix ''{http.request.local.host} != "100.64.0.10"'' caddyFragments.vpn-client-profiles.extraConfig
    && lib.hasInfix publisherIntegration.linksRoot caddyFragments.vpn-client-profiles.extraConfig
    && lib.hasInfix publisherIntegration.routeConfig caddyFragments.vpn-client-profiles.extraConfig
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
    && machine.services.dnsproxy.settings.listen-addrs == [ "127.0.0.1" ]
    && caddyFragments ? fixture-site
    && builtins.elem "forward-proxy" caddyFragments.fixture-site.capabilities;
in
if !contract then
  throw "Combined external Clan fixture contract failed: ${
    builtins.toJSON {
      inherit publicationPhaseResults;
    }
  }"
else
  {
    all = true;
    inherit
      assetLifecycleResults
      contract
      publicationPhaseContract
      publicationPhaseResults
      ;
  }
