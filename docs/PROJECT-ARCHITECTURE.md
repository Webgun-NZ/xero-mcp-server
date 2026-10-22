# xero-mcp-server Architecture Brief

## Product Summary

Webgun-NZ fork of `XeroAPI/xero-mcp-server`: an MCP server (stdio) that exposes Xero
Accounting and Payroll API operations as tools for Claude. The fork adds repeating invoice
tools (`create-repeating-invoice`, `list-repeating-invoices`, `delete-repeating-invoice`) and
`delete-invoice` (draft and awaiting-approval invoices only), which upstream does not have.
Joel's Claude Code launches the local `dist/index.js` build of branch `feat/repeating-invoices`
against the live Enablr Digital Limited Xero organisation, so these tools issue real invoices
and emails to real clients.

## System Shape

- Application type: Node.js MCP server over stdio, one tool per Xero operation
- Primary stack: TypeScript, `@modelcontextprotocol/sdk`, `xero-node`, `zod`, vitest
- System of record: Xero (the server holds no state of its own)
- Critical external integrations: Xero Accounting API (invoices, repeating invoices, contacts)

## Code Layout

- `src/tools/<verb>/*.tool.ts`: zod input schema + MCP response text, built with `CreateXeroTool`
- `src/handlers/*.handler.ts`: Xero API calls, return `XeroClientResponse<T>`, never throw to the tool
- `src/helpers/`: pure builders/formatters (unit tested under `src/helpers/__tests__`)
- `src/clients/xero-client.ts`: auth (custom connection client_credentials, or bearer token)

## Core Workflows

1. Create a repeating invoice template: validated by `buildRepeatingInvoice` (dates, period,
   due date, line items, email flags only on AUTHORISED ACCREC). An AUTHORISED template with
   `approvedForSending` emails real invoices to the contact on every run.
2. List repeating invoices, optionally filtered by contact (contact ID must be a uuid before it
   is interpolated into the Xero `where` clause).
3. Delete a repeating invoice template (status DELETED; already generated invoices unaffected).
4. Delete an invoice: allowed only when the current status is DRAFT or SUBMITTED; anything
   else (AUTHORISED, PAID, VOIDED, DELETED) must be refused, never voided or altered.

## Data and State Boundaries

- Tenant boundary: a custom connection resolves exactly one tenant (`tenants[0]`)
- Canonical entities: Invoice, RepeatingInvoice, Contact
- Irreversible operations: invoice deletion, repeating invoice deletion, any template that
  emails clients (`approvedForSending`)
- Derived vs source-of-truth: Xero is the only source of truth; the tool output is display text

## Security and Access Rules

- Auth model: env vars `XERO_CLIENT_ID`/`XERO_CLIENT_SECRET` (custom connection) or
  `XERO_CLIENT_BEARER_TOKEN`; injected by a wrapper from 1Password, never written to disk
- RBAC model: none in the server; the Xero app's scopes are the boundary
- Sensitive data surfaces: error text returned to the model must not include tokens or auth
  headers (`formatError` exists for this, see upstream #173)
- Injection risk: any user-supplied value placed in a Xero `where` filter must be validated

## Operational Robustness Requirements

- Queue/retry rules: none; each tool call is one synchronous API call
- Idempotency requirements: create tools are not idempotent; a retried create makes a
  duplicate template, so tools must not retry internally
- Reconciliation/failure recovery: a failed call returns an error string and changes nothing
- Observability/audit requirements: Xero's own history records every change

## UI Verification Requirements

None. There is no UI; verification is unit tests plus a live call through the MCP.

## Phases or Milestones

- `repeating-invoices`: create/list/delete repeating invoice tools
- `delete-invoice`: draft-only invoice deletion
