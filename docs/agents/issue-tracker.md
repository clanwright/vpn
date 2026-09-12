# Issue tracker: GitHub

Issues and task specifications live in GitHub Issues for
`clanwright/vpn`. Use the `gh` CLI with the existing authentication.

## Sources of truth

- GitHub Issues own actionable task scope, status, and acceptance criteria.
- `docs/backlog.md` records roadmap context and cross-cutting constraints.
  Link actionable items to their issues instead of duplicating task status.
- Current implemented behavior belongs in canonical project documentation.
- Temporary plans and investigation artifacts belong in ignored `.work/`.

Existing backlog entries remain until explicitly migrated or revised.

## Skill operations

- "Publish to the issue tracker": create a GitHub issue.
- "Fetch the relevant ticket": read its body, labels, and comments.
- Use an explicit repository when operating outside this checkout.
- Pass multiline issue bodies and comments through a file.
- Publish comments only when the user's request authorizes communication.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Wayfinding

A map is an issue labelled `wayfinder:map`.
Link child tickets using GitHub sub-issues; if unavailable, use a task
list in the map and a `Part of #<map>` reference in each child.

Child types use `wayfinder:research`, `wayfinder:prototype`,
`wayfinder:grilling`, or `wayfinder:task`.

Use native issue dependencies when available; otherwise record
`Blocked by: #<number>` references. Choose the first open, unassigned
child in map order whose blockers are all closed.

Claim by assigning the driving developer. On completion, record the
result and evidence, close the child, and link the decision from the map.

## Authorization

Tracker configuration and readiness labels do not grant permission
for protected operations. Apply the repository's approval boundaries.
