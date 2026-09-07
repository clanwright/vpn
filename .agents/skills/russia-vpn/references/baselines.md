# Baseline protocols and existing installations

Checked 2026-09-07 against the linked official documentation. These remain useful
for existing working setups and controlled comparisons; there is no evidence
here that all installations are blocked or that any is universally reachable in
Russia. Inspect the actual implementation before translating option names into
Mihomo, sing-box, mobile apps or other frontends.

## WireGuard

WireGuard is an authenticated UDP tunnel, not browser camouflage. `AllowedIPs`
selects peer traffic and defines allowed source prefixes; the surrounding client
or network manager decides installed routes. Check those routes separately and
make full-tunnel prefixes intentional for both IPv4 and IPv6. `Endpoint` selects
the peer being dialed, while endpoint roaming can update it.

Leave `PersistentKeepalive` off unless idle NAT/firewall state needs preserving;
upstream's 25-second example is a starting point for that use, not anti-DPI tuning.
Handshake, route correctness, sustained transfer and idle reconnect are separate
checks. Keep stock WG distinct from an AWG profile with active extensions.
[Quick start](https://www.wireguard.com/quickstart/),
[cross-platform configuration model](https://www.wireguard.com/xplatform/).

## OpenVPN

UDP is a performance candidate if it passes; TCP/443 is a separately tested
compatibility fallback. TCP-over-TCP may worsen loss recovery and is not a
universal performance fix. The protocol's TLS control plane does not make the
whole connection ordinary browser HTTPS.

Keep certificate verification and supported modern `data-ciphers`.
`tls-crypt-v2` uses per-client protection for the control channel; it differs from
`tls-auth` and shared `tls-crypt` and does not prove DPI resistance. On supporting
OpenVPN 2.6 configurations, `force-cookie` requires compatible clients; do not
break older clients incidentally while changing hardening. Validate both peers,
not just the server parser.
[OpenVPN 2.6 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html),
[control-channel protection](https://build.openvpn.net/doxygen/group__tls__crypt.html).

## Trojan

Use a matching TLS identity and real fallback service. In the original Trojan
client, retain `ssl.verify` and `verify_hostname`; set `sni` to the certificate
hostname. Check trust-store/full-chain behavior on the actual platform. These
field names are implementation-specific, not a portable sing-box/Xray snippet.

Server `remote_addr`/`remote_port` designate the fallback; align ALPN with that
service and verify unauthenticated traffic reaches it. A valid certificate with
an incompatible backend still fails plausibility/compatibility checks. Avoid
invented cipher lists or turning off verification to repair a hostname mismatch.
TLS fallback does not hide endpoint IP/ASN or reproduce every browser behavior.
[Original implementation configuration](https://trojan-gfw.github.io/trojan/config.html),
[protocol](https://trojan-gfw.github.io/trojan/protocol.html).

## Shadowsocks 2022

This encrypted TCP/UDP proxy has a random-looking wire image, not an HTTPS
handshake. Keep its security properties separate from censorship camouflage;
a compatible ShadowTLS wrapper is a different design with additional requirements.

Verify actual SIP022 support on both ends; generic “Shadowsocks” support may
mean older AEAD only. For `2022-blake3-aes-128-gcm` and
`2022-blake3-aes-256-gcm`, use correctly sized random base64 keys (16 and 32 bytes,
respectively), never a human password or legacy password derivation. Keep clocks
correct and use an implementation enforcing replay/timestamp checks. Test TCP
and UDP separately, including packet-size behavior; don't reimplement the
protocol from this skill.
[SIP022 specification](https://shadowsocks.org/doc/sip022.html),
[configuration reference](https://shadowsocks.org/doc/configs.html).
