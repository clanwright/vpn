# Domain docs

## Layout

Single-context: an optional root `CONTEXT.md` for domain vocabulary
and `docs/adr/` for architectural decision records.

Create these lazily when domain modeling resolves terms or decisions.
If absent, proceed using the existing canonical documentation.

## Before exploration

Read the documents relevant to the task:

- `README.md`: project overview and documentation index.
- `docs/architecture.md`: architecture and ownership boundaries.
- `docs/contracts.md`: module contracts.
- `docs/package-authority.md`: package authority.
- Relevant `clanServices/*/README.md`: module behavior.
- `docs/operations/`: operator procedures.
- `docs/backlog.md`: roadmap context and unresolved decisions.

If `CONTEXT.md` exists, use its vocabulary.
If `docs/adr/` exists, read decisions relevant to the affected area.

## Documentation ownership

Keep current behavior in the canonical documents above.
A glossary defines terms; an ADR records a decision and its rationale.
Link to existing documentation instead of copying contracts into
a second specification layer.

Surface conflicts with an ADR explicitly before changing the decision.
Keep temporary plans and unfinished investigations in `.work/`.
