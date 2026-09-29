{ lib }:
let
  manualGroup = "Ручной";
  autoGroup = "Авто";
  # Client-visible names that generated connections must never take.
  reservedNames = [
    manualGroup
    autoGroup
    "GLOBAL"
    "DIRECT"
    "REJECT"
    "REJECT-DROP"
    "PASS"
    "PASS-RULE"
    "COMPATIBLE"
    "EXTERNAL-REJECT"
  ];
  separator = " · ";
  protocolLabels = {
    naiveproxy = "Naive";
    vless-xhttp = "VLESS";
    amneziawg = "AWG";
    mieru = "Mieru";
    anytls = "AnyTLS";
    trusttunnel = "TrustTunnel";
  };
  # Unicode regional indicator symbols; two of them form a flag emoji.
  regionalIndicators = {
    A = "🇦";
    B = "🇧";
    C = "🇨";
    D = "🇩";
    E = "🇪";
    F = "🇫";
    G = "🇬";
    H = "🇭";
    I = "🇮";
    J = "🇯";
    K = "🇰";
    L = "🇱";
    M = "🇲";
    N = "🇳";
    O = "🇴";
    P = "🇵";
    Q = "🇶";
    R = "🇷";
    S = "🇸";
    T = "🇹";
    U = "🇺";
    V = "🇻";
    W = "🇼";
    X = "🇽";
    Y = "🇾";
    Z = "🇿";
  };
  flagFor =
    countryCode:
    lib.concatMapStrings (letter: regionalIndicators.${letter}) (lib.stringToCharacters countryCode);
  validText =
    value:
    builtins.isString value
    && builtins.stringLength value <= 64
    && builtins.match "[^[:cntrl:][:space:]]([^[:cntrl:]]*[^[:cntrl:][:space:]])?" value != null;
  validLabel = value: validText value && !(builtins.elem value reservedNames);
  validCountryCode = value: builtins.isString value && builtins.match "[A-Z]{2}" value != null;
  labelType = lib.types.addCheck lib.types.str validLabel // {
    description = "display label without control characters or surrounding whitespace, at most 64 bytes, not a reserved group name";
  };
  countryType = lib.types.addCheck lib.types.str validText // {
    description = "country name without control characters or surrounding whitespace, at most 64 bytes";
  };
  countryCodeType = lib.types.addCheck lib.types.str validCountryCode // {
    description = "ISO 3166-1 alpha-2 country code in uppercase";
  };
  displayType = lib.types.submodule (_: {
    options = {
      label = lib.mkOption {
        type = labelType;
        description = "Short provider label shown after the country, for example A.";
      };
      country = lib.mkOption {
        type = lib.types.nullOr countryType;
        default = null;
        description = "Country name shown after the flag; set together with countryCode.";
      };
      countryCode = lib.mkOption {
        type = lib.types.nullOr countryCodeType;
        default = null;
        description = "ISO 3166-1 alpha-2 code used to render the flag; set together with country.";
      };
    };
  });

  # Provider label: the consumer display label, or the machine name.
  providerLabel = provider: (provider.display or null).label or provider.machine;
  providerBaseName =
    provider:
    let
      display = provider.display or null;
      country = if display == null then null else display.country or null;
      countryCode = if display == null then null else display.countryCode or null;
    in
    if (country == null) != (countryCode == null) then
      throw "vpn-client-profiles: provider display country and countryCode must be set together for ${provider.machine}/${provider.instanceId}"
    else if country == null then
      providerLabel provider
    else
      "${flagFor countryCode} ${country}${separator}${providerLabel provider}";

  # Resolves unique names for entries { key, base, kind }. A base name stays
  # unchanged unless it collides; colliding entries gain their kind, and a
  # remaining collision gains an ordinal starting at 2. The external composer
  # applies the same rule to subscription nodes.
  resolveNames =
    entries:
    let
      bases = map (entry: entry.base) entries;
      countOf = value: list: builtins.length (builtins.filter (candidate: candidate == value) list);
      qualified = map (
        entry:
        entry
        // {
          name =
            if countOf entry.base bases > 1 || builtins.elem entry.base reservedNames then
              "${entry.base}${separator}${entry.kind}"
            else
              entry.base;
        }
      ) entries;
      firstFree =
        seen: name: ordinal:
        let
          candidate = "${name} ${toString ordinal}";
        in
        if builtins.elem candidate seen then firstFree seen name (ordinal + 1) else candidate;
      resolved =
        builtins.foldl'
          (
            state: entry:
            let
              name =
                if builtins.elem entry.name state.seen then firstFree state.seen entry.name 2 else entry.name;
            in
            {
              seen = state.seen ++ [ name ];
              names = state.names // {
                ${entry.key} = name;
              };
            }
          )
          {
            seen = reservedNames;
            names = { };
          }
          qualified;
    in
    resolved.names;
in
{
  inherit
    manualGroup
    autoGroup
    reservedNames
    separator
    protocolLabels
    flagFor
    labelType
    displayType
    providerLabel
    providerBaseName
    resolveNames
    ;
}
