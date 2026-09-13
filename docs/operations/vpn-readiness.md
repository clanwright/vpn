# VPN startup readiness and consumer acceptance

AWG and Mieru startup guards check local configuration readiness during
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

## Mieru

Mieru's management RPC can remain alive even if the proxy fails to bind. Its
startup guard therefore checks that the main service process owns the TCP
listener on the configured port. A different process's socket must not satisfy
readiness. Runtime firewall, authentication, relay and restart acceptance is
specified in [Mieru operations](mieru.md); none is executed by this repository.
