{ lib }:
let
  ipv4Octet = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])";
  validDnsLabel =
    label:
    builtins.stringLength label <= 63 && builtins.match "[a-z0-9]([a-z0-9-]*[a-z0-9])?" label != null;
  validDnsName =
    name:
    builtins.stringLength name > 0
    && builtins.stringLength name <= 253
    && builtins.all validDnsLabel (lib.splitString "." name);
  looksLikeIpv4 = value: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" value != null;
  isPrivateAddress =
    host:
    host == "::1"
    || builtins.match "127\\.${ipv4Octet}\\.${ipv4Octet}\\.${ipv4Octet}" host != null
    || builtins.match "10\\.${ipv4Octet}\\.${ipv4Octet}\\.${ipv4Octet}" host != null
    || builtins.match "192\\.168\\.${ipv4Octet}\\.${ipv4Octet}" host != null
    || builtins.match "172\\.(1[6-9]|2[0-9]|3[01])\\.${ipv4Octet}\\.${ipv4Octet}" host != null
    ||
      builtins.match "100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.${ipv4Octet}\\.${ipv4Octet}" host
      != null;
  isLoopbackAddress =
    host:
    host == "::1" || builtins.match "127\\.${ipv4Octet}\\.${ipv4Octet}\\.${ipv4Octet}" host != null;
  forbiddenUserRuleModifier =
    rule:
    let
      normalized = lib.toLower rule;
      lineHasImportantModifier =
        line:
        builtins.any (
          modifierTail:
          let
            commaSeparated =
              lib.replaceStrings
                [
                  " "
                  "\t"
                  "\r"
                ]
                [
                  ","
                  ","
                  ","
                ]
                modifierTail;
            terminated = "${commaSeparated},";
          in
          lib.hasPrefix "important," terminated
          || lib.hasPrefix "important=" terminated
          || lib.hasInfix ",important," ",${terminated}"
          || lib.hasInfix ",important=" ",${terminated}"
        ) (lib.drop 1 (lib.splitString "$" line));
    in
    lib.hasInfix "dnsrewrite" normalized
    || lib.hasInfix "badfilter" normalized
    || builtins.any lineHasImportantModifier (lib.splitString "\n" normalized);
in
{
  types = {
    dnsName = lib.types.addCheck lib.types.str validDnsName;
    privateAddress = lib.types.addCheck lib.types.str isPrivateAddress;
    rewriteAnswer = lib.types.addCheck lib.types.str (
      value: isPrivateAddress value || (!looksLikeIpv4 value && validDnsName value)
    );
  };

  render =
    {
      privateZones,
      rewrites,
      userRules,
      dnsBindHosts,
      dnsPort,
      unboundPort,
      fallbackPort,
    }:
    let
      domains = lib.concatMap (zone: zone.domains) privateZones;
      rewriteSources = map (rewrite: rewrite.domain) rewrites;
      isWithinZone = name: builtins.any (zone: name == zone || lib.hasSuffix ".${zone}" name) domains;
      conflictsWithLocalDns =
        upstream:
        (upstream.port == dnsPort && builtins.elem upstream.address dnsBindHosts)
        || (
          isLoopbackAddress upstream.address
          && builtins.elem upstream.port [
            dnsPort
            unboundPort
            fallbackPort
          ]
        );
    in
    {
      inherit domains rewriteSources;
      upstreamLines = lib.concatMap (
        zone:
        map (
          upstream:
          "[/${lib.concatStringsSep "/" zone.domains}/]${
            if upstream.address == "::1" then "[::1]" else upstream.address
          }:${toString upstream.port}"
        ) zone.upstreams
      ) privateZones;
      allowRules = lib.concatMap (domain: [
        "@@||${domain}^$important,dnsrewrite"
        "@@||${domain}^$important"
      ]) domains;
      dsGuards = map (domain: "||${domain}^$dnstype=DS") domains;
      renderedRewrites = map (rewrite: rewrite // { enabled = true; }) rewrites;
      validation = {
        uniqueDomains = lib.length domains == lib.length (lib.unique domains);
        safeUpstreams = builtins.all (
          zone:
          lib.length zone.upstreams == lib.length (lib.unique zone.upstreams)
          && builtins.all (upstream: upstream.port > 0 && !conflictsWithLocalDns upstream) zone.upstreams
        ) privateZones;
        uniqueRewriteSources = lib.length rewriteSources == lib.length (lib.unique rewriteSources);
        rewriteSourcesCovered = builtins.all (rewrite: isWithinZone rewrite.domain) rewrites;
        rewriteAnswersClosed = builtins.all (
          rewrite:
          isPrivateAddress rewrite.answer
          || (isWithinZone rewrite.answer && !builtins.elem rewrite.answer rewriteSources)
        ) rewrites;
        userRulesSafe = !builtins.any forbiddenUserRuleModifier userRules;
      };
    };
}
