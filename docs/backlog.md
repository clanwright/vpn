# Open decisions

Actionable implementation work belongs in GitHub Issues under the
[issue-tracker rules](agents/issue-tracker.md). Current behavior belongs in
[architecture](architecture.md), [contracts](contracts.md) and module pages.
Research in [references](../references/README.md) informs decisions without
changing configuration or proving consumer adoption.

## IPv6 routing

Current clients use IPv4 for external resolution and reject external IPv6 while
preserving local IPv6 exceptions. A dual-family policy needs a separate decision
covering DIRECT destinations, protected destinations, protocol/server support,
A/AAAA and FakeIP precedence, TUN capture and failure behavior. Protected traffic
must not silently fall back to DIRECT. Runtime qualification would belong to the
consumer on an IPv6-capable network.

## External subscriptions and client acceptance

External Xray import is implemented; see [issue #7](https://github.com/clanwright/vpn/issues/7)
and the [publisher contract](../clanServices/vpn-client-profiles/README.md#external-subscriptions).
Connecting real subscription secrets and accepting profiles on devices remain
consumer work. Supported protocols and exact-core limitations are recorded in
[client comparison](../references/client-comparison.md); expanding unsupported
combinations needs a separate decision.

Runtime protocol and client scenarios have one owner in
[verification](operations/verify.md#evidence-and-runtime-acceptance) and its linked
runbooks. These checks do not establish consumer adoption or intended-network
availability.

## Sudoku package and design boundary

Sudoku is deferred. Support requires a reviewed official stock nixpkgs package
with a cached exact `x86_64-linux` output under [package authority](package-authority.md).
A local derivation, override or upstream-binary wrapper is not an alternative.
The canonical protocol is [SUDOKU-ASCII/sudoku](https://github.com/SUDOKU-ASCII/sudoku),
not Xray `finalmask`.

Before implementation, resolve individual credential revocation, direct TCP
versus consumer-owned TLS/WSS, decoy placement, client compatibility and manual
versus Auto inclusion. The retained research found a single server master key,
wildcard listener, client-side TLS setting and consumer-owned fallback/DNS;
these findings require current upstream verification before reuse. The
[upstream configuration reference](https://github.com/SUDOKU-ASCII/sudoku/blob/v0.5.0/configs/README.md)
is research, not an approved module specification. No module or deployment is
implied by this backlog entry.

## Consumer endpoint composition

New protocol adoption requires an explicit endpoint, address/port availability
and certificate or decoy ownership. Independent TCP servers cannot share the
same address and port without an approved composition. Address purchase,
listener multiplexing and replacement of existing services are separate scope
decisions. Native Caddy/ACME producer compatibility and runtime evidence are
qualified through [verification](operations/verify.md#evidence-and-runtime-acceptance).

## TCP tuning ownership

BBR, FQ and TCP sysctls belong to the consumer common machine layer. Moving them
requires a separate ownership decision, public contract, checks and release;
it must preserve host applicability and protocol behavior.
