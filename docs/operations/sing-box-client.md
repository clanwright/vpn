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

[Issue #4](https://github.com/clanwright/vpn/issues/4) records three startup
`open UDP connection ... no route to host` errors with SFM 1.14.1 and Naive
150.0.7871.63. The operator confirmed their destination was
`[2001:4860:4860::8888]:443`. This is a public constant in Chromium's IPv6
reachability check, not a consumer endpoint or an address supplied by the profile.

The source trace matches that version:

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
Cronet. The three failed attempts do not establish successful IPv6 packets,
a DNS leak, authentication failure or a site outage. Source inspection does
not replace packet-level evidence on an IPv6-capable network.

The inspected sing-box Naive options and Cronet client options expose no
reachability-probe disable setting. Keep the current generated transport,
DNS and IPv6 routing policy. Do not pin a physical interface, disable host
IPv6, replace stock packages, or suppress all ERROR logs to hide this result.
Eliminating the attempt or changing its diagnostic treatment belongs to the
upstream client; no supported profile-only fix is established here.

An [earlier upstream report](https://github.com/SagerNet/sing-box/issues/4107)
contains the same destination and error. Its reporter closed it with
"Resolved" without a fix or version, so that closure is not evidence of a
shipped correction. Any follow-up should provide only the client/core/Naive
versions, this public probe destination, relative timestamps and counts, the
relevant nonsecret option values, and whether ordinary traffic succeeds on
IPv4-only and IPv6-capable networks. Keep raw logs, profile URLs, credentials
and private interface/address metadata out of the report. External publication
and client tests require their own authorization.

## SFM, Tailscale and LAN routing acceptance

Tracked in [issue #2](https://github.com/clanwright/vpn/issues/2).
The current generator omits both `route_address` and `route_exclude_address`,
while retaining `auto_route`, `strict_route` and `route.auto_detect_interface`.
It matches the omission variant in the
[September 26 operator A/B report](https://github.com/clanwright/vpn/issues/2#issuecomment-5845378043).
With VPN v0.9.4 (`e05e9c6`), SFM 1.14.1 on macOS and Tailscale enabled,
the original 47 IPv4 and 134 IPv6 included routes lost the default interface.
Removing only `route_address` restored websites and all five rule downloads;
`missing default interface` fell from 2 to 0 and
`no available network interface` from 120 to 0. The route to Tailscale DNS
remained in its tunnel. Clash TUN was disabled in both variants.

This is evidence for one local workaround, not completed client acceptance.
LAN, application access to tailnet, sustained transfer, restart and network
switching still need the checks below. The macOS cause and any minimal failing
prefix remain unknown. Three residual startup Naive IPv6 UDP errors belong to
[issue #4](https://github.com/clanwright/vpn/issues/4); they do not establish a
leak or recurrence of the default-interface failure. Shutdown `aborted`
messages in the report were grouped at the operator's tunnel stop.

The inspected Apple implementation starts `NWPathMonitor` and reports an
empty interface with index `-1` when the path is unsatisfied or has no available
interface. Turning off sing-box's `auto_detect_interface` does not disable
this monitor. See the [Apple monitor implementation](https://github.com/SagerNet/sing-box-for-apple/blob/59540eb0e1812bb76a481a9dc3dec6a788f4196f/Library/Network/ExtensionPlatformInterface.swift#L285-L318).
This explains the reported failure mechanism, not why macOS supplied that path.

Run the following comparison only in the consumer's client acceptance
environment. It is not part of the repository gate. Retain a known-working
profile and client settings for rollback; do not publish experimental profiles
or include credentials, subscription URLs, full profiles or unredacted logs in
shared evidence.

1. Record the SFM app and embedded core versions, macOS and Tailscale versions,
   active physical interface, Tailscale exit-node/subnet-router state, and SFM
   `includeAllNetworks`, `excludeDefaultRoute` and `excludeAPNs` settings.
   Keep those settings and the underlying network constant for the comparison.
2. With SFM stopped and Tailscale connected, record the route interface for a
   consumer-selected numeric tailnet IPv4, tailnet IPv6 and LAN destination.
   Establish successful connections to those destinations independently of
   private DNS. Also check the consumer's private names separately.
3. If repeating the historical A/B comparison, use the retained v0.9.4 profile
   as variant A (47 IPv4 and 134 IPv6 included routes). The current generator
   already emits variant B. Record the same route selections and new connections,
   plus a new public proxy connection and a sustained transfer. Capture only
   redacted interface transition timestamps and error counts.
4. Stop SFM. In a disposable local copy of A, remove only the TUN inbound's
   `route_address` key (variant B). Do not replace it with explicit default
   prefixes: that was not the successful experiment. Compare the remaining
   JSON fields for equality before running the controlled comparison.
   Do not add `route_exclude_address` or change `auto_detect_interface`, DNS,
   selectors or SFM settings. Start B and repeat the same observations.
5. Repeat an ordinary stop/start for each variant. A connected indicator,
   cached URL-test result or existing connection is insufficient. Confirm new
   traffic, tailnet/LAN reachability and expected public IPv6 rejection after
   reconnect. Repeat after switching between the intended physical networks,
   recording interface transitions and new connections. Stop the trial and
   restore the retained known-working setup if B loses required access;
   the failing historical A is not a working fallback.

The omission is the generator contract; broad client compatibility remains
pending acceptance. More-specific OS/Tailscale routes may keep local traffic outside the
TUN, but their precedence under simultaneous Network Extensions must be
observed. If local traffic enters sing-box, a `DIRECT` rule does not guarantee
Tailscale egress: automatic interface binding can select the physical NIC.
Adding the old excluded routes would test a different hypothesis and may send
that traffic to the primary physical interface.

| Observation | Interpretation / next step |
| --- | --- |
| B has new public traffic, tailnet/LAN, sustained transfer, reconnect and network-switch success; A reproducibly loses its path | Accept this combination after confirming FakeIP capture and external IPv6 rejection; retain route/interface observations before generalizing to other clients. |
| B starts but loses tailnet or LAN | Reject B as a fix; public connectivity alone fails the requirement. |
| Both lose the default interface | Route-list replacement is insufficient; inspect SFM settings and path transitions without bundling more changes into B. |
| Both pass | The original failure is not reproduced; do not claim its cause or resolution. |

Record per-variant start/reconnect outcomes, numeric and named destination
results, selected interfaces, transfer results and the three error counts
(`missing default interface`, `no available network interface`,
`missing fakeip record`). Keep FakeIP errors separate from path availability.
Confirm that a fresh FakeIP answer in `198.18.0.0/15` reaches the intended
public destination through the tunnel. On an IPv6-capable physical network,
check that an external IPv6 literal is rejected while the intended local and
tailnet IPv6 destinations remain reachable. Failure on an IPv4-only physical
network cannot by itself prove the profile's IPv6 rejection policy.
No universal client compatibility is established by the pure Nix gate or the
single reported A/B result.
