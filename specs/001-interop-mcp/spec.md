# Feature Specification: IRIS InteropMCP — Interoperability Productions as MCP Servers

**Feature Branch**: `001-interop-mcp`

**Created**: 2026-10-19

**Status**: Draft

**Input**: User description: "implemente um agente mcp usando o framework do AI HUB para transformar IRIS Interoperability Productions em servidores mcp. nessa spec iremos usar o exemplo em object script (intersystems) localizado em src/Sample. ou seja temos qeu atingir os objetuvos do PRD mas usando a implementcao do AI HUB em objrct script como demonstrado no pacote samples. prd em @docs/PRD.md use cases em @docs/Use Cases.md e classes de exemplo no dir de @src/Sample/Agent.cls"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Expose Production Business Services as AI-Callable Tools (Priority: P1)

An integration architect marks selected Business Services of a running interoperability
production as available for AI access. An external AI agent (corporate assistant, autonomous
agent, developer tooling) connects using the standard agent-connectivity protocol, requests the
catalog of available tools, and sees each enabled Business Service represented as a callable
tool with a name, a human-readable description, and a structured definition of the parameters
it accepts. The agent then invokes a tool with concrete parameters; the gateway triggers the
corresponding Business Service inside the production and returns the service's response to the
agent.

**Why this priority**: This is the core value of the gateway — protecting the corporate
investment in validated legacy integrations by making them consumable by AI agents without
rewriting any integration code. Every other capability depends on this foundation.

**Independent Test**: With a sample production running and one Business Service enabled for
exposure, an agent client can list tools, see the service represented with its parameter
definition, invoke it with valid parameters, and receive the correct business response —
delivering standalone value with no other story implemented.

**Acceptance Scenarios**:

1. **Given** a running production with a Business Service enabled for AI exposure, **When**
   a connected agent requests the tool catalog, **Then** that service appears as a callable
   tool with description and input parameter definition.
2. **Given** the tool catalog, **When** an agent invokes an exposed tool with valid
   parameters, **Then** the mapped Business Service executes inside the production and the
   agent receives its business response.
3. **Given** a Business Service not enabled for exposure, **When** an agent requests the tool
   catalog, **Then** that service does not appear as a tool.
4. **Given** a developer workstation setup and a networked server setup, **When** an agent
   connects in each mode, **Then** both connections succeed against the same tool catalog.

---

### User Story 2 - Per-Tool Security Guardrails (Priority: P2)

Every exposed tool carries a security classification that controls how it may be executed:
Read-Only (agent may execute autonomously), Write/Stateful (execution requires validated
parameters and caller authorization), and Critical (execution requires explicit approval from
a human operator before anything happens).

**Why this priority**: AI agents acting directly on transactional legacy systems is the
largest adoption risk of this feature. Guardrails make the gateway safe to turn on, which is a
precondition for production use.

**Independent Test**: With three Business Services exposed, one per classification, invoking
the read-only tool executes immediately; the write tool is rejected without proper
authorization and executes with it; the critical tool is queued as a pending approval and only
executes after a human approves it.

**Acceptance Scenarios**:

1. **Given** a read-only tool, **When** an authorized agent invokes it, **Then** it executes
   immediately with no approval step.
2. **Given** a write/stateful tool, **When** an agent invokes it without required
   authorization, **Then** execution is refused with a clear explanation; **When** invoked
   with valid authorization, **Then** it executes.
3. **Given** a critical tool, **When** an agent invokes it, **Then** no execution starts and
   an approval request is created; **When** a human operator approves, **Then** execution
   proceeds; **When** the operator rejects, **Then** nothing executes and the calling agent
   is informed.

---

### User Story 3 - Full Traceability of AI-Triggered Executions (Priority: P3)

Every tool invocation made by an AI agent is recorded as a first-class message in the
production's message history, visible in the platform's standard trace and message browsing
tools, including the origin (which agent/client), the parameters used, timestamps, and the
outcome.

**Why this priority**: Corporate auditability is a stated success measure (100% of AI calls
traceable) and the trust foundation for letting agents operate on legacy systems.

**Independent Test**: Invoke any exposed tool, then open the production's message history in
the standard tooling and locate the execution record with origin metadata, parameters, and
durations.

**Acceptance Scenarios**:

1. **Given** a successful tool invocation, **When** an operator opens the message history in
   the standard trace tooling, **Then** the invocation appears with agent origin, parameters,
   and timing information.
2. **Given** a failed tool invocation, **When** the operator inspects the message history,
   **Then** the record shows the failure outcome and error details.

---

### User Story 4 - Long-Running Operations with Async Status (Priority: P4)

Some integrations take longer than an interactive agent can reasonably wait. For exposed
tools whose execution exceeds the interactive wait window, the gateway returns immediately
with a processing reference; the agent can then poll for status and retrieve the final result
once processing completes.

**Why this priority**: Required for realistic long-running integrations (batch processing,
regulatory queries) but not needed for the core interactive loop delivered by Story 1.

**Independent Test**: Invoke a tool backed by a simulated long-running service, receive a
processing reference immediately, poll it while in progress and after completion, and receive
the final result.

**Acceptance Scenarios**:

1. **Given** an exposed tool whose execution takes longer than the wait window, **When** an
   agent invokes it, **Then** the agent receives a processing reference immediately.
2. **Given** a pending processing reference, **When** the agent polls while work is still in
   progress, **Then** the status reports in-progress.
3. **Given** a pending processing reference, **When** the agent polls after completion,
   **Then** the final business result is returned.
4. **Given** an unknown or invalid processing reference, **When** the agent polls it, **Then**
   a clear not-found error is returned.

---

### Edge Cases

- What happens when the backing Business Service is disabled or the production is stopped
  while a tool is exposed? The gateway refuses the invocation with a clear, agent-readable
  error and the catalog stops offering the unavailable tool.
- How does the system handle invalid, missing, or mistyped parameters coming from a language
  model? The gateway validates parameters against the tool's definition before execution and
  returns a descriptive error that helps the agent correct the call.
- What happens when two different Business Services would map to the same tool name? The
  gateway refuses to publish an ambiguous catalog and reports the naming conflict at
  discovery time.
- What happens when an unauthenticated or unauthorized client attempts to connect or invoke?
  The attempt is refused and recorded for security review.
- What happens to a pending approval that nobody acts on? It remains pending with no
  execution and can be cancelled by an operator; it never executes automatically.
- What happens when many agents invoke the same tool concurrently? Each invocation is traced
  independently with its own message record and result.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST scan a running interoperability production and build a tool catalog
  from the Business Services explicitly enabled for AI exposure via configuration or class
  annotation.
- **FR-002**: System MUST generate, for each exposed tool, a name, a human-readable
  description, and a structured input parameter definition derived from the service's request
  message structure, in a form language models can consume.
- **FR-003**: System MUST answer agent requests for the tool catalog with all currently
  exposed tools and their definitions.
- **FR-004**: System MUST execute the mapped Business Service inside the production and return
  its business response when an agent invokes an exposed tool with valid parameters.
- **FR-005**: System MUST be consumable by standard agent clients both from local development
  environments and from remote networked deployments.
- **FR-006**: System MUST support a security classification per exposed tool: read-only,
  write/stateful, or critical.
- **FR-007**: System MUST execute read-only tools immediately without any approval step.
- **FR-008**: System MUST require validated parameters and caller authorization for
  write/stateful tools before execution.
- **FR-009**: System MUST queue critical tool executions as pending human approvals, MUST NOT
  execute them before explicit approval, and MUST NOT execute them if the request is rejected.
- **FR-010**: System MUST record every tool invocation in the production's message history —
  visible in the platform's standard trace tooling — including agent origin, parameters,
  timestamps, and outcome.
- **FR-011**: System MUST return a processing reference immediately for executions exceeding
  the interactive wait window and MUST let agents poll status and retrieve results afterwards.
- **FR-012**: System MUST validate all incoming tool parameters against the tool's definition
  before execution and return descriptive, agent-readable errors on failure.
- **FR-013**: System MUST refuse invocations whose backing Business Service is disabled or
  unavailable, return a clear error, and keep the published catalog consistent with actual
  availability.
- **FR-014**: System MUST NOT publish an ambiguous tool catalog; duplicate tool names MUST be
  detected and reported as an error at catalog build time.
- **FR-015**: System MUST require authenticated access in networked or production deployments;
  unauthenticated access is permitted only for local development environments.
- **FR-016**: System MUST emit operational logs at all levels (debug through error) for every
  gateway operation, including catalog builds, invocations, guardrail decisions, and approvals.
- **FR-017**: System MUST expose health and status information about the gateway and the
  underlying production for operational monitoring.
- **FR-018**: System MUST record security-relevant events (denied calls, rejected
  authorizations, approval decisions) as part of the audit trail.

### Key Entities *(include if feature involves data)*

- **Exposed Tool**: The representation of one Business Service for AI agents; attributes
  include name, description, input parameter definition, security classification, backing
  service reference, and enabled state.
- **Business Service**: An existing, validated integration endpoint inside an interoperability
  production, with a defined request message structure.
- **Tool Invocation**: One execution attempt by an agent; attributes include invoker identity,
  tool, parameters, start/end timestamps, status (executed, pending approval, rejected,
  failed), result, and linked message record.
- **Approval Request**: A pending human decision for a critical tool invocation; attributes
  include requesting invocation, decision (approved/rejected/pending), approver identity, and
  decision timestamp.
- **Security Classification**: The policy level assigned to a tool (read-only, write/stateful,
  critical) determining its execution pathway.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An integration developer with an agent-capable client completes a first
  successful tool invocation against an existing production in under 30 minutes, versus days
  of custom connector development.
- **SC-002**: 100% of AI-initiated tool executions are retrievable as audit records containing
  origin, parameters, and duration.
- **SC-003**: Enabling the gateway causes zero regression in the legacy production: identical
  behavior and no measurable throughput degradation under the same workload, measured before
  and after.
- **SC-004**: Changes to which Business Services are exposed are reflected in the tool catalog
  without any manual code change in agent or gateway code.
- **SC-005**: 100% of critical tool executions complete only after a recorded human approval,
  with zero unapproved executions.
- **SC-006**: In a guided demonstration, an operator resolves the representative backoffice
  scenario (verify a payment and update a customer's delivery address) using only natural
  language through an agent connected to the gateway.

## Assumptions

- **Personas**: Integration architects configure exposure; AI agents and assistants consume
  tools; backoffice operators and support staff use agents for daily tasks; auditors and
  security teams read traces and approval records.
- **Demo scope**: The gateway itself is production-agnostic. The Sample package will host a
  small demo production (e.g., a payment-verification service and a customer-update service,
  mirroring Use Case 1 of docs/Use Cases.md) used for the acceptance scenarios above. The
  other use-case domains (industrial, logistics, compliance, autonomous reporting) are
  illustrative targets, not separate deliverables.
- **Interactive wait window**: Default of 30 seconds, configurable per deployment and per
  tool; beyond it, the async reference behavior of FR-011 applies.
- **Authentication**: Production/networked deployments use the platform's standard web
  application authentication; the unauthenticated setup used by the existing sample is
  acceptable only for local development.
- **Approvals**: Human approvals use the platform's standard pending/queue mechanisms; there
  is no auto-execution and no automatic expiry execution of pending approvals.
- **Deployment**: The feature runs as a containerized workload consistent with the project
  constitution (container-oriented architecture, comprehensive logging, monitoring, security
  by design).
- **Dependency (mandated implementation approach)**: The solution MUST be implemented with the
  platform's native AI framework in ObjectScript, following the patterns demonstrated in the
  existing Sample package (`Sample.Agent`, `Sample.ToolSet`, `Sample.Tools`,
  `Sample.MCPService`, `Sample.MCPSetup`): a ToolSet defines the exposed tools, an MCP service
  dispatches the protocol, and a setup routine provisions the endpoint. The embedded-Python
  bridge alternative mentioned in docs/PRD.md is out of scope for this feature; the PRD's
  objectives (auto-discovery, schema generation, sync-over-async, guardrails, native
  traceability, dual connectivity) remain the acceptance bar.
- **Dependency**: An existing, validated interoperability production with enabled Business
  Services must be available in the target environment.
- **Out of scope (v1)**: Purpose-built approval or monitoring UIs (platform-standard tooling
  is used), production-initiated calls toward agents, and tooling for authoring new
  productions.
