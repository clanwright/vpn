{ lib }:
{
  machine,
  publisherManifest,
  domain,
  sameCanonical ? false,
}:
let
  publisher = machine.clanwright.vpn.publishers.vpn-client-profiles;
  site = machine.services.caddy.virtualHosts.${domain};
  text = site.extraConfig;
  connect = machine.clanwright.vpn.naiveproxy.connectRoute;
  proxySite = machine.services.caddy.virtualHosts."site.example.invalid";
  proxyText = proxySite.extraConfig;
  publicSite = machine.services.caddy.virtualHosts."dns.example.invalid";
  privateSite = machine.services.caddy.virtualHosts."adguard.example.invalid";
  publisherRoute = publisher.routeConfig;
  contains = needle: haystack: lib.hasInfix (builtins.unsafeDiscardStringContext needle) haystack;
  before =
    first: second: value:
    contains first value
    && contains second value
    &&
      builtins.stringLength (builtins.head (lib.splitString first value))
      < builtins.stringLength (builtins.head (lib.splitString second value));
  ordered =
    value:
    before "log_skip" "# fixture-alias-route" value
    && before "@naive_proxy_connect" "# fixture-alias-route" value
    && before "# fixture-alias-route" "@vpn_client_profile_site_" value
    && before "@vpn_client_profile_site_" "# fixture-terminal-fallback" value;
  alias = if sameCanonical then "site-alias.example.invalid" else "profiles-alias.example.invalid";
  fragment = machine.sops.templates."naiveproxy-vpn-fixture.caddy";
  cert = machine.security.acme.certs.fixture;
  publicationScript =
    machine.systemd.services.${lib.removeSuffix ".service" publisher.publicationUnit}.script;
  preservesContext =
    value: target:
    let
      expected = builtins.getContext value;
      actual = builtins.getContext target;
    in
    builtins.all (key: actual ? ${key} && actual.${key} == expected.${key}) (
      builtins.attrNames expected
    );
  attachedOnce =
    target:
    contains connect target
    && builtins.length (lib.splitString (builtins.unsafeDiscardStringContext connect) target) == 2
    && preservesContext connect target;
  numericWrongListenerGuard =
    value:
    contains "{http.request.local.port} != 443" value
    && !(contains ''{http.request.local.port} != "443"'' value);
  artifactPaths = lib.concatMap (
    profile: map (artifact: toString artifact.templatePath) profile.artifacts
  ) publisherManifest.profiles;
in
{
  actualNativeOrder = ordered text;
  logBeforeAliasNegativeControl = !ordered (lib.replaceStrings [ "log_skip" ] [ "" ] text);
  publisherBeforeAliasNegativeControl =
    !ordered (
      lib.replaceStrings
        [ "@vpn_client_profile_site_" "# fixture-alias-route" ]
        [ "# fixture-alias-route" "@vpn_client_profile_site_" ]
        text
    );
  fallbackBeforePublisherNegativeControl =
    !ordered (
      lib.replaceStrings
        [ "@vpn_client_profile_site_" "# fixture-terminal-fallback" ]
        [ "# fixture-terminal-fallback" "@vpn_client_profile_site_" ]
        text
    );
  canonicalOwnerAndAliases =
    site.owner == (if sameCanonical then "fixture:site" else "fixture:publisher")
    && site.serverAliases == [ alias ]
    && site.useACMEHost == "fixture"
    && site.forwardProxy == sameCanonical
    && site.hostName == (if sameCanonical then ":443" else domain);
  fullAuthenticatedSelectedCatchall =
    attachedOnce proxyText
    && lib.hasPrefix "route {" (lib.strings.trim connect)
    && contains "method CONNECT" connect
    && contains ''{http.request.local.host} == "192.0.2.10"'' connect
    && contains "{http.request.local.port} == 443" connect
    && contains "import ${fragment.path}" connect
    && contains "basic_auth cHJvYmU " fragment.content
    && contains "deny 0.0.0.0/8" fragment.content;
  explicitPublicHostFullPolicy =
    attachedOnce publicSite.extraConfig
    && attachedOnce text
    && before "@naive_proxy_connect" "@adguard_doh_wrong_listener" publicSite.extraConfig
    && publicSite.hostName == "dns.example.invalid"
    && !publicSite.forwardProxy;
  numericListenerGuards =
    builtins.all numericWrongListenerGuard [
      privateSite.extraConfig
      publicSite.extraConfig
      text
    ]
    && !(contains ''{http.request.local.port} == "443"'' connect);
  quotedPortRegressionRejected =
    !numericWrongListenerGuard (
      lib.replaceStrings [ "{http.request.local.port} != 443" ] [ ''{http.request.local.port} != "443"'' ]
        privateSite.extraConfig
    );
  privateHostExcluded =
    privateSite.listenAddresses == [ "100.64.0.10" ]
    && privateSite.hostName == "adguard.example.invalid"
    && !privateSite.forwardProxy
    && !(contains "method CONNECT" privateSite.extraConfig)
    && !(contains "@naive_proxy_connect" privateSite.extraConfig);
  mixedListenerScopePreserved =
    if sameCanonical then
      site.listenAddresses == [ "192.0.2.10" ]
    else
      site.listenAddresses == [
        "192.0.2.10"
        "100.64.0.10"
      ]
      && contains connect text
      && !(contains ''{http.request.local.host} == "100.64.0.10"'' connect);
  selectedCatchallAndOrdinaryCoverDeclarations =
    proxySite.hostName == ":443"
    && proxySite.listenAddresses == [ "192.0.2.10" ]
    && machine.services.caddy.virtualHosts."dns.example.invalid".hostName == "dns.example.invalid"
    && machine.services.caddy.virtualHosts."dns.example.invalid".listenAddresses == [ "192.0.2.10" ];
  artifactDependenciesPreserved =
    artifactPaths != [ ]
    && builtins.all (
      path:
      builtins.getContext path != { }
      && contains path publicationScript
      && preservesContext path publicationScript
    ) artifactPaths;
  canonicalPublisherGuard =
    contains publisherRoute text
    && lib.hasPrefix "route {" (lib.strings.trim publisherRoute)
    && contains "host ${domain}" publisherRoute
    && !(contains alias publisherRoute)
    && !(contains "host " publisher.logConfig)
    && contains "log_skip" publisher.logConfig;
  nativeCertificateIdentity =
    cert.domain == "example.invalid"
    && builtins.elem "*.example.invalid" cert.extraDomainNames
    && cert.directory == "/var/lib/acme/fixture"
    && cert.dnsProvider == "timewebcloud"
    && cert.group == "acme"
    &&
      cert.credentialFiles.TIMEWEBCLOUD_AUTH_TOKEN_FILE
      == machine.sops.secrets."fixture-dns-api-token".path
    && machine.security.acme.defaults.dnsProvider == null
    && machine.security.acme.defaults.webroot == null
    && machine.security.acme.defaults.listenHTTP == null
    && cert.s3Bucket == null
    && builtins.all (reader: builtins.elem reader cert.reloadServices) [
      "caddy.service"
      "adguardhome.service"
      "sing-box.service"
      "trusttunnel.service"
    ];

  connectBeforeAliasNegativeControl =
    !ordered (lib.replaceStrings [ "@naive_proxy_connect" ] [ "" ] text);
  aliasBeforeConnectNegativeControl =
    !ordered (
      lib.replaceStrings
        [ "@naive_proxy_connect" "# fixture-alias-route" ]
        [ "# fixture-alias-route" "@naive_proxy_connect" ]
        text
    );
}
