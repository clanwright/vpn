# TrustTunnel consumer integration and acceptance

The [TrustTunnel module](../../clanServices/trusttunnel/README.md) runs the
stock endpoint 1.1.0 with an HTTP/2-only outer transport. Repository
verification evaluates Nix contracts and source hygiene. It does not start the
endpoint, run its parser, create a listener, or establish client traffic.

## Consumer preparation

Select an unused TCP port, an exact public IPv4, and a publicly trusted
certificate whose identity matches the configured domain. Bind the consumer's
ACME certificate name and expose only the selected IPv4 and TCP port. The
module copies the certificate and key into systemd credentials and restarts on
renewal. Do not add an `ExecReload` based on SIGHUP: endpoint 1.1.0 reloads only
`hosts.toml`, while existing systemd credential copies do not change until a
new unit activation.

Configure the host system resolver to the consumer's own AdGuard Home
addresses, then provide the same numeric IPv4 list as `dnsResolverIPv4s`.
TrustTunnel resolves tunneled TCP hostnames through the system resolver; its
`--dns-upstream` option affects exported client settings and is not a server
resolver setting. The module does not install, configure, start, or order
AdGuard Home. Its egress guard permits the declared resolver addresses only on
TCP/UDP port 53.

The module asserts equality with the NixOS `networking.nameservers` option.
That option alone does not prove the effective NSS path or exclude resolver
sources added through DHCP, systemd-resolved, or other consumer configuration;
verify the process's actual resolver and fallback behavior during acceptance.

Supply a separate runtime SOPS password for every device. Use raw unpadded
base64url with a length of 1 through 64 bytes and no newline. Credential changes
restart the service because endpoint 1.1.0 loads them only at startup. Use the
same named bindings in the profile publisher. Keep password values and live
profile URLs out of source, commands, logs and review artifacts.

Keep the module's pinned `--loglvl info`. Endpoint 1.1.0 debug and trace paths
can format connection authentication data into logs.

Mihomo profiles use TrustTunnel with `quic: false`, UDP enabled, the exported
SNI and certificate verification enabled. The module does not create official
client exports and does not add a sing-box outbound. Both failed CONNECT and
non-CONNECT authentication return 404; this avoids a proxy-authentication
challenge but is incompatible with clients that wait for a 407 challenge.

## Destination and protocol boundaries

The endpoint's `allow_private_network_connections = false` rejects private and
non-global destinations in its native forwarding paths. That native check is
retained, but it does not by itself enforce the agreed IPv4-only boundary for
literal IPv6 destinations. The dedicated service identity is therefore covered
by an nftables output guard which preserves replies to the exact TCP listener,
permits only the declared DNS exceptions, denies non-public IPv4 ranges, and
denies all IPv6. The systemd sandbox also excludes `AF_INET6`.

Only `[listen_protocols.http2]` and direct forwarding are generated. There is
no outer UDP listener, HTTP/1.1, QUIC/HTTP/3, ICMP raw socket, ClientRandom or
source-CIDR rules file, reverse proxy, ping/speedtest endpoint, or metrics
listener. Consumer overrides must not weaken the service identity, capability
set, address families, templates, listener ingress, nftables table, or its
lifecycle binding to `nftables.service`.

## Separate runtime acceptance

Before adoption, verify on an authorized consumer machine with the exact stock
package and generated configuration:

- Startup, shutdown, certificate renewal, credential restart, permissions and
  absence of credentials or rendered TOML in logs and error reporting.
- Main-process ownership of the exact IPv4 TCP listener, no listeners on other
  local IPv4 addresses or IPv6, and no external UDP listener.
- Positive authentication for each intended Mihomo core, 404 for bad CONNECT
  and non-CONNECT authentication, and device-specific credential revocation.
- TCP upload/download and UDP relay over HTTP/2, sustained transfer beyond
  1 GiB, idle behavior, interruption/reconnect, RSS and outbound socket counts.
- Denial of literal and DNS-resolved loopback, RFC1918, link-local, CGNAT,
  metadata, documentation/reserved, IPv4-mapped IPv6 and native IPv6 targets
  for both TCP and UDP, including a changing DNS answer.
- DNS through every declared resolver on TCP/UDP port 53, denial of other ports
  on those addresses, and continued tunnel replies to private-source clients.
- Firewall start, stop, restart and reload failures: the endpoint must not remain
  usable without its module-owned guard.

Endpoint issue #140 reports unresolved memory growth and an HTTP/2 flow-control
panic in an older deployment whose locked H2 dependency remains in 1.1.0.
Issue #144 reports a connection which stopped recovering without enough detail
to establish a cause. Treat these as bounded soak and recovery scenarios, not
as confirmed defects in every deployment.

Reachability on Dom.ru, T-Mobile and Yota remains separate client acceptance.
Record endpoint and client versions, region, target network, sustained
application transfer and reconnect behavior. A successful import, TLS
handshake, connected badge, or repository gate does not establish that result.
