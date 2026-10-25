# Phase 0 Research: IRIS InteropMCP

**Feature**: specs/001-interop-mcp | **Date**: 2026-10-19

## R1. Tool exposure mechanism on the AI HUB framework

**Decision**: At catalog build time, the gateway scans the production's Business Services
enabled for exposure and **generates + compiles an ObjectScript `%AI.Tool` subclass**
(`br.musketeers.InteropMCP.GeneratedTools`) containing one tool method per enabled service, included by a
static `br.musketeers.InteropMCP.ToolSet` (`%AI.ToolSet`) that also carries the `get_invocation_status`
tool. The `Sample.MCPService` pattern (`%AI.MCP.Service` with `SPECIFICATION` parameter,
dispatched by a Type-18 web application) exposes the ToolSet over MCP.

**Rationale**: This matches the sample package patterns exactly (`Sample.ToolSet` XData with
`<Include>`, `Sample.Tools` with methods/queries as tools, `Sample.MCPSetup` web app
creation) and satisfies FR-002/SC-004: per-service tools with real typed parameters and
descriptions, regenerated on catalog rebuild with no manual code changes. Verified against
official docs: AI Hub ObjectScript SDK — "A tool is an instance of %AI.Tool whose methods an
agent can call"; MCP Server page — "the iris-mcp-server binary, an MCP gateway that bridges
LLM clients to InterSystems IRIS MCP server endpoints" (stdio clients are bridged to the
IRIS endpoint; the IRIS side is always the web application).

**Alternatives considered**:
- One generic tool `invoke_business_service(name, json)` — rejected: flat schema is weaker
  for LLM parameter accuracy, and per-tool guardrails/audit degrade to runtime string checks.
- Pure runtime dynamic dispatch (no generated class) — rejected: `XData` ToolSets are
  statically defined in the framework; code generation at build time is the framework-
  aligned way to get dynamic catalogs.

## R2. Business Service discovery & per-service annotation

**Decision**: Enablement and classification are declared on the Business Service class via
class parameters: `AIGATEWAY` (classification: `readonly` | `write` | `critical`), optional
`AIGATEWAYDESC` (agent-facing description), `AIGATEWAYASYNC` (force queued execution),
`AIGATEWAYWAIT` (per-tool wait-window override). The registry reads these via class
definition metadata; unannotated services are never exposed (FR-001, FR-003).

**Rationale**: Parameter-based annotation is the lowest-friction, code-adjacent mechanism
and is trivially discoverable without storing external config that can drift from code.
Matches "expor os Business Services habilitados com base em anotações ou parâmetros de
classe" in the PRD.

**Alternatives considered**: External registry table only (drifts from deployed code);
central JSON config file (breaks container-immutability principle, extra failure mode).

## R3. Invocation pipeline (Ens.Director)

**Decision**: Tool methods call a shared `br.musketeers.InteropMCP.Invoker` that uses the documented
"Invoking a Business Service Directly" pattern: `##class(Ens.Director).CreateBusinessService()`
then `ProcessInput(request, .response)` for the synchronous path. For tools flagged async
(annotation or wait-window overflow) the invoker queues the request and returns the
invocation ID immediately; `get_invocation_status` (a tool in the ToolSet) polls
`br.musketeers.InteropMCP.Invocations` until terminal state and returns the stored result.

**Rationale**: Officially supported pattern (IRIS docs, Less Common Tasks → "Invoking a
Business Service Directly"); keeps executions inside the production's normal message flow so
`Ens.MessageHeader` records them natively (FR-010, PRD "Rastreabilidade Nativa").

**Alternatives considered**: Direct `OnProcessInput` calls bypassing Ens.Director —
rejected: would fragment traceability and bypass production lifecycle checks; Python
embedded bridge — rejected by spec mandate (ObjectScript AI HUB approach).

## R4. Guardrails enforcement point

**Decision**: Guardrails are enforced **inside each generated tool method** before any
invocation: `readonly` → immediate; `write` → schema validation + caller authorization check;
`critical` → create `br.musketeers.InteropMCP.Approvals` record and return a pending-approval answer with
no execution. Approve/reject happens through the admin API (R6); only an approved state
releases the invocation. Enforcement lives in `br.musketeers.InteropMCP.Guardrails` so every generated
tool shares one audited code path (FR-006–009, FR-018).

**Rationale**: Single choke point is testable and cannot be bypassed by catalog
regeneration; keeping the decision outside `Ens.Director` avoids touching production
behavior (zero-regression, SC-003).

**Alternatives considered**: Policies inside ToolSet XData (framework audit policies exist
but require console access — the sample itself comments this "does not work in MCP
servers"); post-hoc filtering after invocation — rejected: violates FR-009.

## R5. Schema generation from Ens.Request

**Decision**: `br.musketeers.InteropMCP.SchemaMapper` maps request class property metadata to the tool's
input parameter definition (typed method parameters on the generated tool): `%String`,
`%Integer`, `%Numeric`, `%Boolean`, `%Date`/`%TimeStamp` (string format), lists → arrays.
Unmapped types fall back to string with a description note. Required = properties without
defaults and not nullable, per class metadata.

**Rationale**: PRD FR "Conversão automática de propriedades de classes ObjectScript de
solicitação para esquemas de parâmetros válidos para LLMs" — property metadata is the single
source of truth; typed generated methods give the framework native parameter validation on
top of FR-012.

**Alternatives considered**: Hand-written JSON Schema per tool — rejected: not automatic,
breaks SC-004.

## R6. Admin API (catalog build, approvals, health)

**Decision**: Plain ObjectScript ClassMethods documented as the admin contract:
`br.musketeers.InteropMCP.Registry.BuildCatalog()` / `.ListTools()` / `.SetEnabled()`; `br.musketeers.InteropMCP.Approvals.ListPending()` /
`.Approve(id, approver)` / `.Reject(id, approver, reason)`; `br.musketeers.InteropMCP.Health.GetStatus()`.
A thin REST dispatch class may wrap these later for external dashboards; v1 uses class
methods + terminal (platform-standard tooling per spec out-of-scope note).

**Rationale**: Keeps v1 dependency-free, container-provisionable via `Setup.cls` bootstrap,
and consistent with the spec's "platform-standard tooling" assumption.

**Alternatives considered**: Immediate REST API + React dashboard — rejected: explicitly
out of scope for v1 (spec Assumptions), added later without contract changes.

## R7. Security posture of the MCP endpoint

**Decision**: The provisioned web application authenticates with platform authentication
and a least-privilege role (`%DB_IRISAPP` + gateway-specific resource) in all non-dev
environments; unauthenticated access (as in `Sample.MCPSetup`, `AutheEnabled=64`) is
permitted only when the environment is explicitly marked local-dev. Security-relevant
events (denied calls, rejected authorizations, approval decisions) are recorded both in the
invocation store and the platform audit log (FR-015, FR-018).

**Rationale**: The sample's `:%All` + unauthenticated setup is acceptable for a sandbox demo
only; constitution "Security by Design" and FR-015 require the hardening path. Documented as
a deliberate sample deviation.

## R8. Live-instance verification (open item, not a spec unknown)

**Decision**: The IRIS 2026.3 instance was reachable during planning (version confirmed) but
the HTTP endpoint flapped mid-session, so class-level introspection of `%AI.*` could not be
captured. All framework facts above are grounded in official docs + the committed sample
code; **implementation phase MUST verify** on the live instance before writing code: (a)
`%AI.ToolSet`/`%AI.MCP.Service` presence and member signatures, (b) compile of a minimal
generated tool class, (c) Type-18 web app creation via `Security.Applications`. This is a
first task in the tasks phase, not a NEEDS CLARIFICATION.

**Rationale**: Docs + samples are consistent; only instance quirks (EAP build differences)
remain, and they surface immediately at compile time.

## R9. Testing strategy

**Decision**: `%UnitTest` suites per gateway component (SchemaMapper, Guardrails, Invoker,
Registry) plus an end-to-end suite driving the generated tools against the demo production
(run with `/noload`). Python MCP-client smoke tests under `python/smoke/` validate the
protocol-facing contract from an external agent's perspective (list → call → status).
Line coverage target ≥ 90% on `br.musketeers.InteropMCP` package per constitution quality gates.

**Rationale**: Component isolation catches guardrail/regression issues cheaply; the Python
harness proves the actual consumer experience (SC-001, SC-006) and satisfies the
constitution's dual-backend stack.

## R10. Logging & monitoring design

**Decision**: `br.musketeers.InteropMCP.Log` wraps platform logging with levels DEBUG→ERROR, emitted from
every gateway component with component tags (`registry`, `guardrail`, `invoker`, `approval`,
`mcp`). `br.musketeers.InteropMCP.Health.GetStatus()` reports production running state, catalog size,
pending approvals, and last invocation timestamps — consumable by container-level monitoring
(FR-016, FR-017, constitution).

**Rationale**: One logging helper avoids level/format drift across components; health shape
covers the monitoring principle without introducing new infrastructure.
