# Adopt the revised integration contracts

This is a breaking source API change. Stable Clan module IDs are unchanged.
Publishing a release, editing a consumer and deploying it remain separate
authorized operations. Repository evaluation does not adopt the change anywhere.

## Provider and rendering API

- Upgrade provider exports to `schemaVersion = 2`. Old versions are rejected.
- Set `clientPrivateKeySecretName` for every AWG peer to the existing consumer
  SOPS binding. No credential rotation or renaming is required by the new API.
  Client private-key bindings must be distinct from each other and from the
  gateway private-key and header-protection-key bindings.
- Read AWG public keys from `transportMetadata.peers`; `peerPublicKeys` is removed.
- Replace `lib.clientProfiles` usage with the publisher role and its typed NixOS
  integration output. Do not import internal renderer files.

## AdGuard composition

Remove `ui.domain`, `ingress.*` and `acme.certName` from role settings. Supply
`tls.certificateFile` and `tls.privateKeyFile` as runtime bindings. The consumer
must provide file permissions to the AdGuard service and connect certificate
renewal to the exported `reloadUnits`.

Read `config.clanwright.dns.adguardhome.integration` for `uiBackend` and
`dohBackend`. Declare Caddy sites, public/private listeners, TLS validation of
the DoH backend, firewall exposure and any Tailscale ordering in the consumer.
The repository's [consumer fixture](../../checks/fixtures/example-clan.nix)
demonstrates composition with Network. It is evaluation data, not an operator
entrypoint or a module to import into production.

Move conditional private upstream entries and native AdGuard rewrite settings
into `dns.privateZones` and `dns.rewrites`. Preserve the consumer's actual names,
addresses and friendly CNAME targets only in the consumer. A minimal fictional
shape is:

```nix
dns.privateZones = [
  {
    domains = [ "admin.example.invalid" "internal.example.invalid" ];
    upstreams = [ { address = "10.20.0.53"; port = 53; } ];
  }
];
dns.rewrites = [
  {
    domain = "admin.example.invalid";
    answer = "node.internal.example.invalid";
  }
];
```

Remove rules using `dnsrewrite`, `badfilter` or `important` modifiers from
`filtering.userRules` when private zones are enabled; keep ordinary consumer
allow/deny rules there. Move supported exact DNS aliases into typed
`dns.rewrites`; native rewrites retain priority over the generated zone
exemptions.

Review enabled remote filter feeds for more-specific important blocks of direct
private names. The module-owned exceptions prevent consumer rules from canceling
the closure, but cannot assert the current content of downloaded feeds. A feed
conflict affects the answer, not the private-only forwarding route.
Replace any imperative protection toggle with `filtering.enable`. Do not migrate
an imperative `filtering_enabled = false` state: disabling the engine also
disables rewrites and is outside this contract.

Before adoption, ensure every private resolver handles the protected suffixes
without forwarding them to public DNS. Confirm consumer-owned listeners,
firewall, client DNS routes, and HTTPS names and certificates separately. A
repository evaluation cannot inspect the external resolver or prove runtime
failure routing.

## Profile publication

Remove publisher `caddyBindIPv4`, `tailnetIPv4`, `acmeCertName` and links-page
`tailnetOnly` settings. These are consumer exposure decisions. Client-facing
`configGatewayDomain`, `publicIPv4` and `edgeDomain` remain renderer inputs.
Choose a distinct `localMachineName` runtime label for each active publisher
instance on a machine; duplicate roots or unit names are rejected during evaluation.
Use a distinct `configGatewayDomain` and Caddy virtual host for each publisher.
The exported route configurations use the same URL layout and cannot share one
host; duplicate gateway domains are rejected without regard to letter case.

Use `config.clanwright.vpn.publishers.<instance>` for static route configuration,
runtime roots, reader group, unit names and public-asset status. Grant Caddy the
reader group. Bind the public profile site and private links page explicitly.
Keep the supplied log suppression: secret path tokens must not enter access logs.
Do not use runtime Caddy imports, add a Caddy requirement on the publisher, or
reload/restart Caddy on profile-secret changes.

The publisher adds only its publication unit to secret restart targets. A shared
binding may still have a separate provider-owned restart target, for example a
NaiveProxy server password; that is independent of profile publication.

Secret publication is withdrawn before regeneration and becomes visible only
after the complete generation succeeds. A failure makes the profile endpoint
unavailable, including the links page; unrelated sites continue to operate.
Already downloaded profiles on clients are not revoked by removing their
publication. Credential revocation at provider gateways remains consumer-owned.

Public rule assets use persistent state, while profiles and tokens stay under
`/run`. First publication waits for required assets and retries automatically.
Existing accepted public assets remain available during refresh failures without
a hard expiration. Wire the nonsecret status to consumer monitoring; stale lists
may omit new routing entries. Do not treat public cache retention as permission
to retain revoked credentials.

## Verification and delivery

Evaluate the consumer composition against the exact intended revision and run
the complete [repository gate](verify.md). Preserve its artifacts and review the
final diff. Evaluate certificate permissions, static routing, log suppression,
private links access and absence of Caddy/publisher lifecycle coupling.

These checks do not prove startup, parser acceptance or network behavior. Do not
perform runtime tests, builds, VM tests or deployed-machine probes as repository
verification. Historical access logs and any token-rotation response are separate
consumer operations, not part of this source migration.
