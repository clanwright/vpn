# Release a version

Release publication is an explicit owner operation. Before publishing, start
from a reviewed revision with a clean worktree and complete the local
[verification gate](verify.md). Confirm that the release description covers the
final public surface, the version is an exact SemVer tag, and consumer
integration has been evaluated against that revision.

Create and push the signed tag only within an approved publication task. Verify
the remote tag resolves to the reviewed commit. Consumer adoption is a separate
transaction: update its exact flake input, verify provenance and run its
cross-domain and production closure gates before any deployment is considered.

Publishing a tag does not authorize deployment, provider or DNS mutation,
credential changes, secret generation, backup operations or live endpoint
tests.
