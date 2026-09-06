# Backlog

## TCP performance policy

BBR, FQ and the existing TCP sysctl policy remain in the consumer's common
machine layer. A future change may evaluate moving that policy into this domain,
but it requires a separate ownership decision, public contract, checks and
release. It must preserve host applicability and must not silently alter VPN
protocol behavior.

## Package-source cleanup

Replace the manual NaiveProxy package only when the selected official package
stream provides the required functionality and the candidate passes domain and
consumer verification.
