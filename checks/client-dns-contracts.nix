{
  lib,
  profileTypes,
}:
let
  legacySettings = {
    edgeDomain = "edge.example.invalid";
    publicIPv4 = "192.0.2.10";
  };
  oneEndpoint = [
    {
      domain = "dns-one.example.invalid";
      ipv4 = "192.0.2.53";
    }
  ];
  threeEndpoints = [
    {
      domain = "dns-a.example.invalid";
      ipv4 = "192.0.2.53";
    }
    {
      domain = "dns-b.example.invalid";
      ipv4 = "198.51.100.53";
    }
    {
      domain = "dns-c.example.invalid";
      ipv4 = "203.0.113.53";
      port = 8443;
      path = "/fixture-dns-query";
    }
  ];
  evalEndpoints =
    value:
    (lib.evalModules {
      modules = [
        {
          options.clientDnsEndpoints = lib.mkOption {
            type = lib.types.nullOr profileTypes.clientDnsEndpointsType;
            default = null;
          };
        }
        { config.clientDnsEndpoints = value; }
      ];
    }).config.clientDnsEndpoints;
  schemaAccepts = value: (builtins.tryEval (builtins.deepSeq (evalEndpoints value) true)).success;
  normalize =
    clientDnsEndpoints:
    profileTypes.normalizeClientDnsEndpoints (legacySettings // { inherit clientDnsEndpoints; });
  normalizationRejects = value: !(builtins.tryEval (builtins.deepSeq (normalize value) true)).success;
  normalizedLegacy = profileTypes.normalizeClientDnsEndpoints legacySettings;
  normalizedOne = normalize oneEndpoint;
  normalizedThree = normalize threeEndpoints;
  sharedIPv4Endpoints = oneEndpoint ++ [
    {
      domain = "dns-two.example.invalid";
      ipv4 = "192.0.2.53";
    }
  ];
in
{
  compatibility = {
    omittedUsesLegacyEndpoint =
      normalizedLegacy == [
        {
          domain = "edge.example.invalid";
          ipv4 = "192.0.2.10";
          port = 443;
          path = "/dns-query";
        }
      ];
    nullUsesLegacyEndpoint = normalize null == normalizedLegacy;
    oneEndpointDefaultsApplied =
      normalizedOne == [
        {
          domain = "dns-one.example.invalid";
          ipv4 = "192.0.2.53";
          port = 443;
          path = "/dns-query";
        }
      ];
    threeEndpointsPreserveOrderAndOverrides =
      normalizedThree == [
        {
          domain = "dns-a.example.invalid";
          ipv4 = "192.0.2.53";
          port = 443;
          path = "/dns-query";
        }
        {
          domain = "dns-b.example.invalid";
          ipv4 = "198.51.100.53";
          port = 443;
          path = "/dns-query";
        }
        {
          domain = "dns-c.example.invalid";
          ipv4 = "203.0.113.53";
          port = 8443;
          path = "/fixture-dns-query";
        }
      ];
  };
  schema = {
    oneEndpointAccepted = schemaAccepts oneEndpoint;
    threeEndpointsAccepted = schemaAccepts threeEndpoints;
    nullAccepted = schemaAccepts null;
    unknownFieldRejected =
      !(schemaAccepts [ ((builtins.head oneEndpoint) // { bootstrap = "public"; }) ]);
    invalidDomainRejected =
      !(schemaAccepts [ ((builtins.head oneEndpoint) // { domain = "DNS.EXAMPLE.INVALID"; }) ]);
    invalidIPv4Rejected =
      !(schemaAccepts [ ((builtins.head oneEndpoint) // { ipv4 = "192.0.2.999"; }) ]);
    invalidPathRejected = !(schemaAccepts [ ((builtins.head oneEndpoint) // { path = "dns-query"; }) ]);
  };
  normalizer = {
    nonListRejected = normalizationRejects { domain = "dns-one.example.invalid"; };
    emptyRejected = normalizationRejects [ ];
    unknownFieldRejected = normalizationRejects [
      ((builtins.head oneEndpoint) // { bootstrap = "public"; })
    ];
    invalidDomainRejected = normalizationRejects [
      ((builtins.head oneEndpoint) // { domain = "dns.example.invalid."; })
    ];
    invalidIPv4Rejected = normalizationRejects [
      ((builtins.head oneEndpoint) // { ipv4 = "192.00.2.53"; })
    ];
    invalidPortRejected = normalizationRejects [ ((builtins.head oneEndpoint) // { port = 0; }) ];
    invalidPathRejected = normalizationRejects [
      ((builtins.head oneEndpoint) // { path = "/dns-query?x=1"; })
    ];
    duplicateDomainRejected = normalizationRejects (
      oneEndpoint ++ [ ((builtins.head oneEndpoint) // { ipv4 = "198.51.100.53"; }) ]
    );
    sharedIPv4Accepted =
      normalize sharedIPv4Endpoints == [
        {
          domain = "dns-one.example.invalid";
          ipv4 = "192.0.2.53";
          port = 443;
          path = "/dns-query";
        }
        {
          domain = "dns-two.example.invalid";
          ipv4 = "192.0.2.53";
          port = 443;
          path = "/dns-query";
        }
      ];
  };
}
