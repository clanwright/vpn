# Release a version

Release publication requires owner authorization. Prepare the final public
contracts, current documentation and necessary module-owned producer pins;
review the complete change independently. Use the owner-selected exact SemVer
tag. Check remote tag and GitHub Release identities first; report a collision
with its exact SHA rather than reusing or overwriting an existing tag.

Run the complete [verification gate](verify.md) on the final declared and locked
published inputs, without candidate overrides. Retain measured logs, source and
lock hashes. Network's published native API must be compatible with the shipped
integration fixtures. Preserve VPN's Clan/nixpkgs and exact package authority;
do not refresh unrelated inputs. Access qualification is separate from the
shipped flake/fixture graph and creates no implicit release dependency.

Commit the reviewed, verified sources and verify a clean worktree and matching
source content before publication. Delivery requires the independent review and
local gate above; this repository has no hosted CI or mandatory PR workflow.
Honor configured hooks and remote branch protections; never bypass signatures.
Create a signed annotated tag, verify its signature and peeled commit, push without force, and
verify the remote default-branch and tag identities. Check remote state before
retrying a publication whose result is unknown.

Publish concise release notes describing supported capabilities, public
contracts, retained decisions, producer revisions and actual verification limits.
GitHub supplies the tagged
source archives; this repository does not publish application binary assets.
Confirm the release URL, tag identity and expected asset list.

Removal of historical GitHub Releases requires separate owner authorization.
Inventory exact release IDs, notes and assets; retain restoration metadata/assets
outside the active corpus before deleting only the authorized Release objects
after the replacement is verified. Git tags and history remain intact.

Consumer adoption is a separate transaction: update its exact published input,
verify provenance and evaluate its direct and nested graph through public
outputs before production closure gates. Release evidence is subject to the
canonical [PREDEPLOY / NOT OBSERVED boundary](verify.md#evidence-and-runtime-acceptance).
