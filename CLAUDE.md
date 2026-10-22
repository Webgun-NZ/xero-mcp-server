# CLAUDE.md — xero-mcp-server

> Repo-local builder instructions for Claude CLI.

## Project Identity

- Project: `xero-mcp-server`
- Product summary: Webgun-NZ fork of the Xero MCP server adding repeating invoice and draft-invoice delete tools; runs against the live Enablr Digital Xero org (see docs/PROJECT-ARCHITECTURE.md).
- Authoritative architecture doc: `docs/PROJECT-ARCHITECTURE.md`
- Reviewer contract: `AGENTS.md`

## Working Model

- Claude is the primary builder in the real git worktree.
- Codex is the independent reviewer.
- `./scripts/codex-review.sh` is the authoritative review bridge.
- Humans are only brought in for strategic, irreversible, or explicit risk-acceptance decisions.

## Required Reading Order

Before implementing meaningful changes:

1. Read this file
2. Read `AGENTS.md`
3. Read `docs/PROJECT-ARCHITECTURE.md`
4. Read any project-specific docs referenced from that architecture doc

## Non-Negotiable Rules

- Do not mark a task complete without Codex review.
- Use `./scripts/codex-review.sh` for authoritative review, not MCP snippet review.
- Fix all `CRITICAL` and `HIGH` findings before proceeding.
- Escalate to a human only for strategy, ambiguity, or explicit risk acceptance.

## Mandatory Review Workflow

1. Implement the smallest coherent change.
2. Run local checks that make sense for the repo.
3. Run `./scripts/codex-review.sh diff`.
4. Fix findings.
5. Re-run review until the change is safe.
6. For milestone or phase completion, run `./scripts/codex-review.sh approve <label>`.

## Review Triggers

Automatically call the review bridge for:

- auth or session changes
- RBAC or permission changes
- data model or migration changes
- API contract changes
- queue, retry, idempotency, or reconciliation logic
- file upload or export surfaces
- external integration changes
- UI-affecting changes that alter workflow or permissions

## Playwright Verification

When changes affect UI behavior, role gating, workflow state, or critical user journeys:

- run browser verification before final sign-off
- record what was verified and with which role
- do not claim UI verification without evidence

## Human Decision Milestones

Escalate only when:

- requirements are genuinely ambiguous
- there are two materially different architecture directions
- the change affects security, privacy, compliance, or production risk in a non-routine way
- the decision is destructive or difficult to reverse

## Project Specifics

- Core workflows: create/list/delete repeating invoices; delete draft or awaiting-approval invoices
- Security boundaries: Xero creds only via env from 1Password; no tokens in error text; validate anything placed in a Xero `where` filter
- Integrations: Xero Accounting API via xero-node
- Milestone labels or phases: `repeating-invoices`, `delete-invoice`
