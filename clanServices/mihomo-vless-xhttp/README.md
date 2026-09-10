# @clanwright/vpn-mihomo-vless-xhttp

## Purpose and role

The stable module ID `@clanwright/vpn-mihomo-vless-xhttp` provides one independent stock Xray
VLESS/REALITY/XHTTP gateway. It does not share process, configuration, package,
or restart state with Hysteria2.

## Settings

The exact schema and defaults are defined in [`default.nix`](default.nix).
The consumer supplies an exact public `bindIPv4`, endpoint `domain`, per-device
`profiles`, and client publication metadata. Each profile has its own SOPS UUID
secret name and REALITY short ID. `reality.targetHost` names the REALITY target;
port 443, TLS 1.3, and HTTP/2 are fixed policy, and `serverNames` must contain the
target. The XHTTP path must start with `/`; server mode is fixed to `auto`.

The target declarations are configuration preconditions. Pure evaluation cannot
prove the target's live protocol negotiation or certificate SANs; verify those
from each deployment location before activation.

`port` is the public client port and defaults to 443. By default, Xray listens
directly on `bindIPv4:port`. Optional `localListener = { ipv4 = "127.0.0.1";
port = 10443; };` instead binds Xray to that loopback socket. Its `ipv4` defaults
to `127.0.0.1` and must be in `127.0.0.0/8`; its port must be 1–65535. Public endpoint
metadata remains `bindIPv4:port`, so generated clients never use the internal
port. In this mode the public `bindIPv4` must not be a loopback address.

The consumer supplies the public TCP passthrough listener and SNI routing.
It forwards the selected external REALITY names to Xray and its own HTTPS
names to its TLS web server. It must preserve the TLS bytes without terminating
TLS or prepending a PROXY protocol header. The module does not create a router,
Caddy site or service dependency, and keeps the external REALITY target.

## Runtime and secrets

The module uses the native NixOS Xray service with the injected stock Xray
26.3.27 package. SOPS renders one root-only runtime JSON template. UUIDs and the
REALITY private key remain placeholders during Nix evaluation and never enter
the store. Xray runs under systemd's dynamic non-root identity and receives only
`CAP_NET_BIND_SERVICE` when the actual listener uses a privileged port; a high
loopback port needs no capabilities even when the public client port is 443.

The generated inbound uses VLESS `decryption: none`, REALITY `show: false` and
`xver: 0`, XHTTP over TCP in server mode `auto`, and no Vision flow or fallback.
Padding, buffering, and XMUX overrides are omitted so the pinned Xray defaults
apply.

## Export and exposure

Each device short ID is exactly 16 lowercase hex characters (8 bytes).
Short forms and uppercase spellings are rejected, avoiding equivalent
zero-padded/case-varied identities in Xray's decoder.

`vpnProvider` retains protocol `vless-xhttp` and publishes the endpoint,
REALITY target/server names/public key, per-profile short IDs, XHTTP path/mode,
fingerprint, DoH metadata, and secret names. In direct mode the module opens only the exact
`bindIPv4:port` destination through nftables; it does not add a global allowed
TCP port.
The consumer must explicitly enable the nftables firewall backend for direct
mode; that mode rejects disabled firewalls or the iptables backend. With
`localListener`, the module adds no firewall rule. The consumer owns the public
router's exposure, including keeping internal ports inaccessible externally.

Operator checks and activation guidance are in
[`docs/operations/vless.md`](../../docs/operations/vless.md).
