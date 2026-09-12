# Mieru consumer integration and acceptance

The [Mieru module](../../clanServices/mieru/README.md) runs stock Mieru 3.36.0's
`mita` server. Repository verification is pure Nix and static hygiene only.
The runtime scenarios below require a separately authorized consumer environment;
do not run services, application parsers or network probes as repository tests.

Upstream `mita run` can keep its management RPC alive after proxy startup fails.
The module therefore checks that the main process owns a TCP listening socket
on the configured port before activation completes. This local guard is not an
authentication, relay or external-reachability check.

## Consumer preparation

Select an unused TCP port and the intended public IPv4. Native mita binds the
port on wildcard addresses; the module restricts ingress with nftables. A
different service cannot reuse that wildcard port on another address. No TLS
certificate, domain, reverse proxy or UDP ingress is required.

Configure the host's resolver and provide its numeric IPv4 addresses to the
module. Mita uses the system resolver; its DNS option selects the address family,
not upstream servers. The egress guard permits DNS only to the declared addresses
on TCP/UDP 53. A resolver must actually be reachable from the service. A local
resolver or cache remains consumer-owned; the module does not start or reorder
AdGuard Home, Unbound, systemd-resolved or any other DNS implementation.

Supply a separate runtime SOPS password for each device. Use the exact base64url
format documented on the module page. Reuse the same named bindings at the
publisher, and select the provider for eligible device profiles. Values and live
profile URLs must stay out of source, Nix store, commands, logs and review evidence.
Maintain system time synchronization: Mieru authentication depends on clock time.

Mihomo profiles expose Mieru with the normal SELECTIVE/FULL and Auto policy.
Official sing-box profiles continue to require an eligible Naive provider.
The pinned Mihomo implementation supports Mieru TCP and UDP relay; this does not
prove subscription import or operation of a particular GUI/core combination.

## Destination protection

Native `allowPrivateIP=false` and `allowLoopbackIP=false` do not provide a complete
boundary. The stock implementation checks TCP before hostname resolution and
does not recheck individual UDP relay destinations. The module's service-scoped
output rules cover actual IP packets, including destinations obtained through DNS.
The initial egress is IPv4-only; IPv6 on the host is not globally disabled.

The configured resolver's exact DNS port is an intentional exception, not access
to its other services. Keep the mita service identity dedicated. Rules preserve
responses to client-initiated tunnel connections, including private-source clients.
The firewall and service dependency contracts need runtime acceptance; a passing
pure Nix gate only proves that their declarations are present and consistent.

## Separate runtime acceptance

Before adoption, use the exact stock package and actual service sandbox to verify:

- Foreground startup, management socket permissions, runtime config permissions,
  restart and shutdown; no credentials or rendered JSON in service logs.
- Correct ingress IPv4 and port, rejection on every other local address including
  IPv6, no external UDP protocol listener, and failure on a conflicting TCP port.
- Positive and negative password authentication, device-specific revocation and
  clock-skew failure. Do not infer readiness from an active process alone.
- TCP download/upload and UDP relay inside TCP, including sustained transfer,
  idle/reconnect, CPU and memory. Exercise the real Mihomo GUI import path.
- Denial of literal and DNS-resolved loopback, private, link-local, CGNAT and
  metadata destinations for both TCP and UDP. Include a changing DNS answer.
- DNS on the declared resolver's TCP/UDP 53, denial of other ports on that resolver,
  and continued tunnel responses to clients with private source addresses.
- Firewall startup failure, stop/restart and reload failure: proxy service must
  not remain usable without its guards. Consumer firewall composition must not
  bypass or remove them.

Availability on Dom.ru, T-Mobile and Yota remains a separate acceptance result.
No nationwide blocking-resistance or performance guarantee follows from upstream
support or the repository checks.

## Package follow-up

Update to stock 3.36.1 or a later reviewed version only after confirming the exact
Linux output is cached and repeating the package and full repository gate.
Version 3.36.1 optimizes CPU usage and fixes UDP association through an external
SOCKS5 egress. The initial direct-egress configuration does not use that proxy
chain. It does not fix the native destination-filtering gap.
