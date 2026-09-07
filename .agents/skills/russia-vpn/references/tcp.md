# TCP protocol configuration

Read after [selection](protocols.md). Research checked 2026-09-07; recheck
installed versions before using these fields. These are configuration checkpoints,
not deployment-ready profiles or evidence of nationwide RU reachability.

## REALITY and XHTTP

- Server `target` (older `dest`) and allowed `serverNames` must be coherent with
  the target's certificate names and TLS behavior; target is not a client field.
  Do not treat a popular SNI as an allowlist token. Check the actual endpoint
  and unauthorized fallback behavior.
- Match client identity/key material and a supported `fingerprint`; `shortId`
  is even-length hex, at most 16 characters. `serverNames` do not support
  wildcards. Keep keys and authentication material out of examples and logs.
- Inspect version gates such as `minClientVer` before supporting old clients.
  Target choice also affects fallback abuse and traffic consistency; assess
  reachable, plausible targets rather than copying a universal public domain.
  [Official REALITY configuration](https://xtls.github.io/en/config/transports/reality.html).

REALITY is supported with RAW/XHTTP/gRPC, not WebSocket. Check the specific
transport/flow/security combination rather than adding Vision to every VLESS
profile. [Compatibility matrix](https://xtls.github.io/en/config/transport.html).

XHTTP `auto` can select a different mode when security or `downloadSettings`
changes. The researched documentation selects `stream-one` for REALITY, or
`stream-up` with separate download settings. Pinning server mode can reject
other client modes. Check mode, path, headers, buffering and timeouts through
the actual reverse proxy/CDN. `noGRPCHeader`/`noSSEHeader` are targeted
compatibility options, not universal hardening. XMUX request reuse and TCP
connection reuse are distinct; retain upstream defaults until measurements
justify adjustment. [Maintainer XHTTP discussion](https://github.com/XTLS/Xray-core/discussions/4113).

Do not put a REALITY endpoint behind a generic TLS-terminating CDN and assume
its authentication survives; use the provider-supported TLS/HTTP design for
that leg. gRPC is not automatically safer: upstream documents probing and
routing caveats and recommends XHTTP for new designs.
[Official gRPC documentation](https://xtls.github.io/en/config/transports/grpc.html).

Snapshot: [Xray v26.7.28](https://github.com/XTLS/Xray-core/releases/tag/v26.7.28),
2026-07-28, was marked pre-release at research time. This is a researched tag,
not a mandatory version or proof that its defaults apply to Mihomo/sing-box.

## NaiveProxy

Use the maintained stable Chromium-aligned client and compatible Naive server
plugin, not an arbitrary HTTP CONNECT proxy. For TCP/H2 the proxy scheme is
`https://`; `quic://` changes the outer transport to UDP. Keep authentication,
certificate verification and `probe_resistance`; review `hide_ip`/`hide_via`
on the documented server. Serve a real front page and compression, and verify
unauthenticated requests actually reach that site. Restrict local listeners to
the needed interface; a loopback listener is still a local app-visible surface.
[Official setup and protocol rationale](https://github.com/klzgrad/naiveproxy).

Research found stable tag `v150.0.7871.63-1` (2026-07-03). Recent releases added
front-page preambles and stall/idle controls; read release-specific fixes before
setting timeout flags. The `master` branch is not a stable install target.
[Naive releases](https://github.com/klzgrad/naiveproxy/releases).
Browser-like handshakes and padding reduce particular signals, not all traffic
analysis or service-side VPN detection.


## TLS knobs are not interchangeable

A browser-named `fingerprint` imitates part of the handshake, not the complete
browser stack. Upstreams differ: sing-box discourages uTLS and prefers Naive
for this objective, while REALITY requires a compatible fingerprint. Attribute
those positions; neither establishes a nationwide protocol winner. Do not
rotate Chrome/Safari/random values without a controlled reason.

ECH requires compatible client/server configuration and bootstrap. It can hide
the inner name, not the destination IP or local VPN state. An ECH switch alone
does not grant allowlist access. Inspect whether ECH was actually negotiated.

TLS `fragment` and `record_fragment` act at different segmentation layers;
version/OS timing behavior matters. Use one measured comparison for a matching
handshake failure, then check latency and sustained traffic. Do not stack every
fragmentation/spoofing option or mistake it for a remedy for L3 denial.
[sing-box TLS fields and caveats](https://sing-box.sagernet.org/configuration/shared/tls/).

## Community failures that change configuration decisions

Checked through 2026-09-07. These are scoped reports/maintainer resolutions;
recheck whether the deployed build contains a fix before applying a workaround.

| Evidence | Useful action | Limit / status at cutoff |
| --- | --- | --- |
| [Mihomo #3039](https://github.com/MetaCubeX/mihomo/issues/3039), July 2026; [#3132](https://github.com/MetaCubeX/mihomo/issues/3132), 2026-08-20 | Mihomo 1.19.29/1.19.30 reports REALITY client version `1.8.2`; the Xray 26.7.11+ default floor `26.3.27` rejects it. Check the advertised version and server floor before blaming XHTTP or DPI. | Exact floor `1.8.2` was reported working with Xray 26.7.28 on four servers. Lowering the floor broadens accepted clients: prefer compatible clients, or consciously support that generation. Do not blindly set `0.0.0`; this is not a protocol-block bypass. |
| [Xray #5918](https://github.com/XTLS/Xray-core/discussions/5918), April–May 2026 | Compare RAW/REALITY against XHTTP on the same iOS device: the reported Happ/Streisand core 26.2.6 with server 26.3.27 completed TLS but sent no HTTP payload. | A client/transport compatibility lead, not proof all iOS XHTTP fails. Changing XHTTP headers/modes did not fix the reporter's setup. |
| [Xray #6385](https://github.com/XTLS/Xray-core/discussions/6385), June–July 2026 | Inspect CDN response/body and path handling; a reported static-file-only path policy collided with an added trailing slash. | A CDN-origin 403 is a different failure from carrier packet dropping. Moving IDs into headers alone did not satisfy that endpoint. |
| [Xray #5908](https://github.com/XTLS/Xray-core/issues/5908), April 2026 | Check which outbound the health probe actually used and the expected response, then sustained application transfer. | The burstObservatory false-alive report was disputed and not independently reproduced. Do not encode the author's original causal claim as a known Xray bug. |
| [sing-box #4002](https://github.com/SagerNet/sing-box/issues/4002), reported 1.12.21; [v1.13.6](https://github.com/SagerNet/sing-box/releases/tag/v1.13.6), 2026-04-06 | Use a build containing the Naive inbound padding-memory fix; check the server implementation, not only the Chromium client. | Historical fixed security regression, not current evidence against Naive or RKN detection. The fix is in [v1.13.5…v1.13.6](https://github.com/SagerNet/sing-box/compare/v1.13.5...v1.13.6); do not assume an arbitrary fork/backport includes it. |

Community preference is conditional. In the
[April Naive discussion](https://ntc.rkn.quest/t/naive-proxy-пока-лучший-вариант/23843),
one author moved from failed XHTTP/REALITY to Naive while another reported
split upload/download XHTTP working on restricted paths. Operator/version
controls were insufficient for a ranking. Use that disagreement to choose a
second implementation to test, not to declare a universal winner.

Earlier [multi-ISP REALITY reports](https://github.com/net4people/bbs/issues/546)
(November 2025) found that port/mux changes helped some paths and later stopped
helping others. Changing SNI, fragmentation or Vision was not a durable general
cure. Retain such interventions as symptom-specific A/B controls; verify their
current behavior before recommending them.
