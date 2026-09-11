# VPN startup readiness and consumer acceptance

AWG and Hysteria2 startup guards check local configuration readiness during
`ExecStartPost`. A failed guard fails activation and invokes the service's
restart policy. An `active` state is not evidence of an external handshake or
working data transfer, and startup guards are not continuous health monitoring.

Repository verification remains pure Nix evaluation and static source hygiene
as described in [verify.md](verify.md). It checks generated configuration and
failure branches without executing them. The following runtime scenarios belong
to a separately authorized consumer acceptance environment; they are not tests
to run in this repository.

## AWG

Use four synthetic peers with distinct public keys and AllowedIPs. Verify that
all four peer argument groups reach a single `awg set` invocation and that the
installed peer keys and AllowedIPs exactly match the intended configuration.
Check that the interface is up and the reported listen port is the configured
port before activation completes.

Inject a nonzero `awg set` result and separately simulate a successful return
with a missing peer, an unexpected peer, wrong AllowedIPs or wrong listen port.
Each case must fail activation, stop the daemon and run interface/socket cleanup;
an automatic restart must not be mistaken for successful activation. Check that
diagnostics contain no key material or raw command output.

After deployment, independently verify handshake and data transfer for every
intended peer. Failure of a peer that was installed successfully requires its
own diagnosis; missing other peers does not establish its cause or justify a
routing/NAT change.

## Hysteria2

Use synthetic TLS materials delivered through the real unit's `LoadCredential`
mechanism, preserving its service identity and sandbox. Verify that the TLS
paths and `SAFE_PATHS` refer to the same service credential directory, and that
the main Mihomo process owns a UDP socket on the exact configured IPv4 and port
before activation completes.

Independently test rejected TLS paths, invalid TLS materials and a running
Mihomo process without the intended listener. Each must fail activation within
the bounded startup interval. A socket owned by another process, or one bound
to a different address or port, must not satisfy readiness. Retain sanitized
service status and the guard's diagnostic reason without copying credentials
or rendered secret configuration into reports.

After deployment, independently verify external Hysteria2 authentication and
TCP/UDP relay using the intended consumer profile. A local UDP socket alone
does not establish TLS correctness, authentication, firewall reachability or
working transfer.
