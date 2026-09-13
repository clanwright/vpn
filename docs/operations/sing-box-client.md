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

## SFM, Tailscale and LAN routing acceptance

Tracked in [issue #2](https://github.com/clanwright/vpn/issues/2).
The reported vpn 0.9.1 / SFM 1.14.0 / macOS 26.5.2 failure is an initial
`en0` detection followed by `missing default interface` after TUN settings,
then 137 `no available network interface` errors in about seven seconds.
Tailscale remained connected. These are operator observations, not a local
reproduction. The cause of the unavailable path remains unknown.

The inspected Apple implementation starts `NWPathMonitor` and reports an
empty interface with index `-1` when the path is unsatisfied or has no available
interface. Turning off sing-box's `auto_detect_interface` does not disable
this monitor. See the [Apple monitor implementation](https://github.com/SagerNet/sing-box-for-apple/blob/59540eb0e1812bb76a481a9dc3dec6a788f4196f/Library/Network/ExtensionPlatformInterface.swift#L285-L318).
This explains the reported failure mechanism, not why macOS supplied that path.

Run the following comparison only in the consumer's client acceptance
environment. It is not part of the repository gate. Retain the existing
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
3. Start the generated profile unchanged (variant A: 47 IPv4 and 134 IPv6
   included routes). Record the same route selections and new connections,
   plus a new public proxy connection and a sustained transfer. Capture only
   redacted interface transition timestamps and error counts.
4. Stop SFM. In a disposable local copy of the same profile, change only the
   TUN inbound's `route_address` to `["0.0.0.0/0", "::/0"]` (variant B).
   Do not add `route_exclude_address` or change `auto_detect_interface`, DNS,
   selectors or SFM settings. Start B and repeat the same observations.
5. Repeat an ordinary stop/start for each variant. A connected indicator,
   cached URL-test result or existing connection is insufficient. Confirm new
   traffic, tailnet/LAN reachability and expected public IPv6 rejection after
   reconnect. Stop the trial and restore A if B loses required access.

Default routes without exclusions are a candidate, not the selected generator
contract. More-specific OS/Tailscale routes may keep local traffic outside the
TUN, but their precedence under simultaneous Network Extensions must be
observed. If local traffic enters sing-box, a `DIRECT` rule does not guarantee
Tailscale egress: automatic interface binding can select the physical NIC.
Adding the old excluded routes would test a different hypothesis and may send
that traffic to the primary physical interface.

| Observation | Interpretation / next step |
| --- | --- |
| B has new public traffic, tailnet/LAN, and reconnect success; A reproducibly loses its path | Evidence for changing capture routes on this combination; retain route/interface observations before generalizing to other clients. |
| B starts but loses tailnet or LAN | Reject B as a fix; public connectivity alone fails the requirement. |
| Both lose the default interface | Route-list replacement is insufficient; inspect SFM settings and path transitions without bundling more changes into B. |
| Both pass | The original failure is not reproduced; do not claim its cause or resolution. |

Record per-variant start/reconnect outcomes, numeric and named destination
results, selected interfaces, transfer results and the three error counts
(`missing default interface`, `no available network interface`,
`missing fakeip record`). Keep FakeIP errors separate from path availability.
No working universal replacement is established until this evidence exists.
