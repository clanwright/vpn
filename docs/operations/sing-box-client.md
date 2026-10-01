# Sing-box client operations

## FakeIP cache

The generated sing-box profile enables the cache file and sets
`store_fakeip: true`. This preserves the domain-to-FakeIP mapping across an
ordinary SFM service restart and a subscription refresh, provided that SFM
keeps its working directory. Do not clear SFM's working directory during a
normal restart or profile refresh.

The profile deliberately omits `path`, so sing-box uses its documented
`cache.db` default. SFM 1.14.0 passes a persistent `Working` directory to
libbox and starts or reloads the service with an empty override. Consequently,
SFM owns the location of the relative `cache.db`; the subscription does not
embed a device-specific absolute path.

The profile also omits `cache_id`. Upstream describes it only as a keyed store.
The FakeIP implementation accesses top-level FakeIP buckets directly in
sing-box 1.14.0. A `cache_id` therefore
must not be treated as a way to isolate or migrate FakeIP mappings.

Sources:

- [sing-box cache-file reference](https://sing-box.sagernet.org/configuration/experimental/cache-file/)
- [SFM 1.14.0 working-directory selection](https://github.com/SagerNet/sing-box-for-apple/blob/59540eb0e1812bb76a481a9dc3dec6a788f4196f/Library/Network/ExtensionProvider.swift#L101-L149)
- [SFM 1.14.0 starts and reloads with an empty libbox override](https://github.com/SagerNet/sing-box-for-apple/blob/59540eb0e1812bb76a481a9dc3dec6a788f4196f/Library/Network/ExtensionProvider.swift#L232-L241)
- [sing-box 1.14.0 default path and keyed-store setup](https://github.com/SagerNet/sing-box/blob/v1.14.0/experimental/cachefile/cache.go#L82-L113)
- [sing-box 1.14.0 FakeIP buckets](https://github.com/SagerNet/sing-box/blob/v1.14.0/experimental/cachefile/fakeip.go#L15-L190)

### Restart and refresh acceptance

Use a public hostname covered by the generated FakeIP DNS policy. While SFM
is running, confirm its A answer is within `198.18.0.0/15`, record that FakeIP
address and prove traffic through it. A real public address does not exercise
this test. Restart SFM
without clearing its working directory or any DNS cache, then force the same
hostname to the previously recorded FakeIP address and prove traffic again.
Refresh the subscription without clearing caches and repeat with that same
address. This specifically tests preservation of the pre-issued reverse
mapping; a fresh DNS lookup that receives a new allocation is not sufficient.

Repeat once after disconnecting and reconnecting SFM. Record the client/core
version and whether the profile was restarted, refreshed, or re-imported.
Re-import may create new client-owned state and is not covered by the generated
profile contract.

## Switching between Clash and SFM

Clash and SFM have independent cache databases. Even when both clients use
`198.18.0.0/15`, never assume that a FakeIP address allocated by one client has
the same domain mapping in the other.

Use this sequence when switching engines:

1. Quit applications that may retain DNS answers or connections.
2. Stop the currently active VPN client and wait until its tunnel is gone.
3. Flush the operating-system DNS cache. On macOS, an operator may run
   `sudo dscacheutil -flushcache` followed by
   `sudo killall -HUP mDNSResponder`.
4. Clear only an application's DNS/network cache when it provides that control.
5. Start the destination client, then reopen applications and resolve
   destinations again through the destination client.
6. Confirm fresh DNS answers, application traffic, sustained transfer, and one
   reconnect before accepting the switch.

Do not copy either cache into the other client or share one database between
them. Preserve each client's own cache for its subsequent runs. The reset is intentional:
it prevents an application from presenting a stale FakeIP address to an engine
that cannot map it back to the original domain.

### Pre-issued address acceptance

Test both Clash → SFM and SFM → Clash on the intended device. For each direction,
use a harmless, operator-controlled hostname covered by FakeIP policy. Before
switching, record the hostname, its issued FakeIP address, and a non-sensitive
marker in the intended page or response. Keep the hostname in the controlled
request so TLS hostname and certificate verification remain enabled; direct
access to the numeric address without that verification is not this test.

1. Stop the source client, wait until its tunnel is gone, and start the
   destination client without the cache reset above. Before a fresh DNS lookup
   or application restart, make one controlled request to the
   **previously recorded FakeIP address** with the original hostname and normal
   TLS verification. Record whether it fails, reaches the intended content, or
   reaches different content. A coincidental correct result does not show that
   the clients migrated or shared a mapping; rejection is not guaranteed.
2. Apply the switch sequence above to recover: quit the affected application,
   stop the destination client, flush the OS DNS cache, clear only supported
   application DNS/network caches, restart the destination client, and reopen
   that **same application**. Observe a new resolution through the destination
   client and confirm that the application reaches the intended content without
   reusing its cached answer. The new numeric FakeIP may happen to match the
   old one. Confirm new traffic and a reconnect as in step 6.

The accepted recovery is the cache reset and fresh resolution. Once a mapping
has been abandoned, the other client cannot recover it from the generated
profile. The generated cache settings are covered by repository checks; this
cross-client behavior remains pending device acceptance in
[issue #3](https://github.com/clanwright/vpn/issues/3).

## Recovering after a lost SFM mapping

If SFM's working directory or `cache.db` was removed while the OS or an
application still retained `198.18.0.0/15` answers, treat those answers as
unusable. Quit affected applications, stop SFM, flush the OS DNS cache, and
clear only application DNS/network caches where supported. Start SFM, reopen
the applications, and resolve the destinations again. Do not restore or
transplant a Clash cache, and do not invent a `cache_id` to recover the old
mapping.

Repository checks verify the generated cache settings and their stability
across representative profile refresh inputs. They do not execute SFM, inspect
the device database, or prove restart, switch, DNS, or application behavior.
Those properties require client-side acceptance on the intended Apple device.

## Naive startup IPv6 reachability probe

[Issue #4](https://github.com/clanwright/vpn/issues/4) tracks Naive/Cronet startup
IPv6 reachability errors. Chromium uses public `[2001:4860:4860::8888]:443`
for its internal probe; the address does not come from the generated profile.
The source provenance for sing-box 1.14.1 and Naive 150.0.7871.63 is:

- sing-box [v1.14.1 dependencies](https://github.com/SagerNet/sing-box/blob/v1.14.1/go.mod)
  select Cronet Go wrapper `0d28acc44093` and platform libraries `c10c03c318db`.
  The latter pins [Naive `72a06c9`](https://github.com/SagerNet/cronet-go/tree/c10c03c318db/naiveproxy),
  whose [VERSION](https://github.com/SagerNet/naiveproxy/blob/72a06c9fca0e2d228588c7f3074bf7efff3ff686/src/chrome/VERSION)
  is 150.0.7871.63. This is source provenance, not a binary attestation of the
  installed SFM build.
- Chromium's [host resolver](https://github.com/SagerNet/naiveproxy/blob/72a06c9fca0e2d228588c7f3074bf7efff3ff686/src/net/dns/host_resolver_manager.cc#L1531-L1632)
  opens a datagram socket to the constant IPv6 address using port 443 by
  default, then checks the local socket address. That probe path does not send
  a DNS query or application payload. Its result is cached briefly.
- The pinned [Cronet UDP callback](https://github.com/SagerNet/cronet-go/blob/0d28acc44093/naive_client.go#L274-L303)
  invokes its dialer directly and logs the observed error on failure. Its
  [engine setup](https://github.com/SagerNet/cronet-go/blob/0d28acc44093/naive_client.go#L362-L391)
  installs that callback even with QUIC disabled.

This identifies the matching internal probe and explains why `quic: false`,
`udp_over_tcp: false`, an IPv4 proxy endpoint and DNS `ipv4_only` do not prevent
the socket attempt. The routed external-IPv6 reject rule governs captured
application traffic; it is not a filter on every socket created internally by
Cronet. A failed probe does not establish successful IPv6 packets,
a DNS leak, authentication failure or a site outage. Source inspection does
not replace packet-level evidence on an IPv6-capable network.

The inspected sing-box Naive options and Cronet client options expose no
reachability-probe disable setting. Keep the current generated transport,
DNS and IPv6 routing policy. Do not pin a physical interface, disable host
IPv6, replace stock packages, or suppress all ERROR logs to hide this result.
Eliminating the attempt or changing its diagnostic treatment belongs to the
upstream client; no supported profile-only fix is established here.

For client follow-up, retain exact client/core/Naive versions, relative error
timestamps/counts and whether ordinary traffic succeeds on IPv4-only and
IPv6-capable networks. Keep raw logs, profile URLs, credentials and private
interface/address metadata out of shared reports. Client tests and external
publication require their own authorization.

## SFM, Tailscale and LAN routing acceptance

Tracked in [issue #2](https://github.com/clanwright/vpn/issues/2).
The current generator omits both `route_address` and `route_exclude_address`,
while retaining `auto_route`, `strict_route` and `route.auto_detect_interface`.
The rationale is retained in [issue #2](https://github.com/clanwright/vpn/issues/2).
A connected status does not establish LAN, application tailnet access, sustained
transfer or reconnect/network-switch behavior.

The inspected Apple implementation starts `NWPathMonitor` and reports an
empty interface with index `-1` when the path is unsatisfied or has no available
interface. Turning off sing-box's `auto_detect_interface` does not disable
this monitor. See the [Apple monitor implementation](https://github.com/SagerNet/sing-box-for-apple/blob/59540eb0e1812bb76a481a9dc3dec6a788f4196f/Library/Network/ExtensionPlatformInterface.swift#L285-L318).
This explains the reported failure mechanism, not why macOS supplied that path.

Run consumer acceptance on each intended client/OS/Tailscale combination.
Retain a known-working profile and client settings for recovery. Keep credentials,
subscription URLs, full profiles and private address/interface metadata out of
shared evidence.

1. Record client/core, macOS and Tailscale versions and SFM
   `includeAllNetworks`, `excludeDefaultRoute` and `excludeAPNs` settings.
2. With SFM stopped and Tailscale connected, establish numeric and named
   tailnet/LAN connectivity and identify the consumer-selected routes.
3. Start the current generated profile. Confirm fresh public application traffic,
   sustained transfer and new numeric/named LAN and tailnet connections. A
   cached URL-test or existing connection is insufficient.
4. Confirm a fresh FakeIP answer in `198.18.0.0/15` reaches the intended public
   destination. On an IPv6-capable physical network, confirm external IPv6
   literals are rejected while intended local/tailnet IPv6 remains reachable.
5. Repeat stop/start, reconnect and switches between intended physical networks.
   Retain redacted transition timings and separate counts for `missing default
   interface`, `no available network interface` and `missing fakeip record`.
   Restore the known-working setup if required access is lost.

More-specific OS/Tailscale routes may keep local traffic outside the TUN; their
precedence under simultaneous Network Extensions requires observation. If
local traffic enters sing-box, `DIRECT` does not guarantee Tailscale egress:
automatic interface binding can select the physical NIC. Adding excluded
routes changes the contract and requires a separate decision.

These are consumer scenarios under the shared
[evidence boundary](verify.md#evidence-and-runtime-acceptance), not repository
tests or universal compatibility claims.
