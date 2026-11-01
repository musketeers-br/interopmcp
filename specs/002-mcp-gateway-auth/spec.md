# Feature Specification: Per-User Authentication and Authorization for the MCP Gateway

**Feature Branch**: `002-mcp-gateway-auth`

**Created**: 2026-10-25

**Status**: Draft

**Input**: User description: "docs/interop-mcp/authentication.md — authentication and authorization for the InteropMCP gateway: Basic auth per IRIS user, least-privilege authorization on the endpoint, identity propagation into the audit trail, idempotent provisioning, and a documented Phase 2 evolution (OAuth, API key, per-tool RBAC)."

## Clarifications

### Session 2026-10-25

- Q: What operating mode should a fresh environment use when setup runs without an explicit mode? → A: Secured by default; demo mode requires an explicit opt-in.
- Q: Should denied authentication and denied entitlement attempts be recorded in the audit trail, or only successful tool invocations? → A: Audit all attempts — successful tool invocations plus denied authentication and denied entitlement attempts.
- Q: How should the gateway distinguish a missing or invalid credential from a valid user who lacks the entitlement in its denial response? → A: Standard 401 for missing or invalid credential, 403 for a valid user without the entitlement.
- Q: What should happen in secured mode when a static backend credential is still configured on the tool-invocation path? → A: Fail setup/start with an actionable error rather than run with the static credential.
- Q: How often should the gateway re-check a caller's entitlement while a session is already open? → A: On every tool request, so revocation takes effect on the next call even within an open session.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Each Agent Client Connects With Its Own Identity (Priority: P1)

An operator configures an agent client (for example, one developer's workspace) with that
person's own corporate directory credential. When the client connects to the gateway and
invokes a tool, the gateway validates the credential against the organization's user directory
and executes the call as that person. A client that presents no credential, or an invalid one,
is refused before any tool can run.

**Why this priority**: Without per-user authentication the gateway cannot tell two consumers
apart. Every other guarantee in this feature — authorization, audit attribution, least
privilege — depends on knowing who is calling.

**Independent Test**: With the gateway in its secured operating mode, one client configured
with a valid credential connects, lists tools, and invokes a read-only tool successfully; a
second client with no credential is refused; a third client with a wrong credential is
refused. Delivers standalone value: only identified callers can use the gateway.

**Acceptance Scenarios**:

1. **Given** the gateway is in its secured operating mode, **When** a client presents a valid
   user credential, **Then** the connection is accepted and tools can be listed and invoked.
2. **Given** the gateway is in its secured operating mode, **When** a client presents no
   credential, **Then** the connection is refused and no tool executes.
3. **Given** the gateway is in its secured operating mode, **When** a client presents an
   invalid credential, **Then** the connection is refused and no tool executes.
4. **Given** two clients authenticated as two different people, **When** each invokes the same
   tool, **Then** both calls execute under their respective identities, with no identity
   bleed between them.

---

### User Story 2 - Access Is Limited to Explicitly Entitled Users (Priority: P2)

A security administrator decides who may use the gateway by granting an entitlement to
individuals or groups. A user who authenticates successfully but has not been granted that
entitlement is denied at the endpoint, before the tool catalog is exposed. Users who hold the
entitlement use the gateway normally.

**Why this priority**: Authentication alone would let every directory user reach every exposed
tool. Least privilege is the control that makes the gateway safe to expose beyond a demo.

**Independent Test**: With the gateway secured, one user holding the entitlement lists tools
and invokes a tool; one valid user without the entitlement is denied before seeing the tool
catalog. Delivers standalone value: only intended users reach the tools.

**Acceptance Scenarios**:

1. **Given** a user with the gateway entitlement, **When** they connect, **Then** the endpoint
   admits them and the tool catalog is available.
2. **Given** a valid user without the gateway entitlement, **When** they connect, **Then** the
   endpoint denies access and no tool catalog or tool result is returned.
3. **Given** an entitlement is revoked from a user, **When** that user makes their next tool
   request, even within an already-open session, **Then** access is denied without any change
   to the gateway's configuration or a reconnect.

---

### User Story 3 - Every Invocation Is Attributed to a Real Person (Priority: P3)

An auditor reviews the invocation history after an incident and can see, for each call, which
person triggered it and when. In the unauthenticated demo mode, calls are attributed to a
clearly labeled local development identity instead of a generic placeholder.

**Why this priority**: Traceability is what makes the gateway defensible in an audit. It is
lower priority than access control because it observes rather than prevents, but it is required
for production acceptance.

**Independent Test**: Two users each invoke a tool, then the invocation history is inspected
and shows each call under the correct distinct identity; a call made in unauthenticated demo
mode shows the local development identity. Delivers standalone value: an auditable trail.

**Acceptance Scenarios**:

1. **Given** an authenticated user invokes a tool, **When** the invocation record is read,
   **Then** it names that user as the caller.
2. **Given** two different authenticated users invoke tools, **When** the records are read,
   **Then** the two records name different callers.
3. **Given** a call made in unauthenticated demo mode, **When** the record is read, **Then**
   the caller is shown as the local development identity, not a generic placeholder.

---

### User Story 4 - Provisioning Is Repeatable and Mode-Aware (Priority: P4)

An operator brings up a fresh environment or re-runs setup on an existing one and chooses
either the open demo mode or the secured mode. Setup creates or reconciles the access
entitlement and the endpoint protection for that mode, and re-running setup leaves the
environment in the same state rather than duplicating or corrupting it.

**Why this priority**: Manual, error-prone security setup is how insecure defaults reach
production. Repeatable provisioning turns the secure configuration into the default path, but
it depends on the access model being defined first.

**Independent Test**: Run setup twice in secured mode; the entitlement and endpoint protection
exist once, unchanged, and a user with the entitlement still connects. Then run setup in demo
mode; the endpoint becomes open and unauthenticated calls succeed under the local development
identity.

**Acceptance Scenarios**:

1. **Given** a fresh environment, **When** setup runs in secured mode, **Then** the gateway
   entitlement and endpoint protection are created and a granted user can connect.
2. **Given** a fresh environment, **When** setup runs without an explicit mode, **Then** the
   environment is provisioned in secured mode and unauthenticated calls are refused.
3. **Given** an environment already provisioned in secured mode, **When** setup runs again in
   secured mode, **Then** no duplicate entitlement is created and behavior is unchanged.
4. **Given** an environment provisioned in secured mode, **When** setup runs in demo mode,
   **Then** the endpoint is open and unauthenticated demo calls succeed.
5. **Given** an environment provisioned in demo mode, **When** setup runs in secured mode,
   **Then** the endpoint requires credentials and rejects unauthenticated calls.

---

### Edge Cases

- **Valid credentials, no entitlement**: The user authenticates but is denied at the endpoint
  with a 403 before the tool catalog is exposed; the response does not reveal credential
  details or the entitlements held by other users.
- **Expired or rotated credential**: The client is refused on the next connection; an
  already-established session ends when the credential is next validated.
- **Static gateway credential configured**: A configured backend credential that overrides the
  caller's credential would collapse all users into one identity. The secured configuration
  must not carry such an override.
- **Credential in logs**: Credentials must not appear in gateway logs, invocation records, or
  error messages, including on failed authentication.
- **Two users invoking concurrently**: Records remain correctly attributed; no shared session
  state leaks one user's identity to another.
- **Entitlement changes during a session**: The change takes effect on the next tool request,
  including within an already-open session; an in-flight call is not retroactively aborted.
- **Demo mode on a reachable network**: Demo mode is unauthenticated by design and must be
  distinguishable from secured mode in configuration and in documentation so it is not
  mistaken for production-ready.
- **Secured mode without transport encryption on a non-local network**: The deployment is
  outside this phase's scope and must be explicitly flagged as unsupported until transport
  encryption is introduced.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The gateway MUST support two explicit operating modes: an open demo mode with
  no caller authentication, and a secured mode that requires caller authentication.
- **FR-002**: In secured mode, the gateway MUST authenticate each caller against the
  organization's existing user directory using the caller's own credential.
- **FR-003**: In secured mode, the gateway MUST refuse a connection that presents no
  credential, and MUST refuse a connection that presents an invalid credential.
- **FR-004**: The gateway MUST pass each caller's credential through unchanged from the agent
  client to the directory that validates it; it MUST NOT substitute a shared service
  credential for the caller's credential on the tool-invocation path.
- **FR-005**: In secured mode, the gateway MUST deny access to an authenticated user who has
  not been granted the gateway entitlement, before any tool catalog or tool result is
  returned.
- **FR-006**: The gateway MUST enforce the entitlement at the endpoint boundary and MUST NOT
  rely on role assignment as the access restriction.
- **FR-007**: The gateway MUST record, for every tool invocation, the identity of the caller
  as established by authentication, and MUST expose that identity through invocation status
  reporting.
- **FR-008**: In demo mode, the gateway MUST attribute invocations to a clearly labeled local
  development identity rather than a generic placeholder.
- **FR-009**: The gateway MUST provide a repeatable setup operation that, for the selected
  mode, creates or reconciles the gateway entitlement and the endpoint protection without
  duplicating existing definitions.
- **FR-010**: Setup MUST be idempotent: running it repeatedly in the same mode MUST leave the
  entitlement and endpoint protection unchanged in effect.
- **FR-011**: Switching an environment between demo mode and secured mode via setup MUST
  change the endpoint's authentication and authorization behavior accordingly.
- **FR-012**: In secured mode, the gateway role MUST carry only the gateway entitlement plus
  the minimum data permissions required by the exposed tools, and nothing broader.
- **FR-013**: The gateway MUST NOT write caller credentials to logs, invocation records, or
  error responses, including on authentication failure.
- **FR-014**: The secured configuration MUST NOT contain a static backend credential on the
  tool-invocation path that would replace the caller's identity. If one is present, setup and
  startup MUST fail with an actionable error naming the offending setting rather than run in
  a state where every caller shares one identity.
- **FR-015**: In secured mode, a user holding the entitlement MUST be able to invoke both
  read-only and write-classified tools subject to the tool's own guardrails.
- **FR-016**: The deployment documentation MUST state that secured mode over unencrypted
  transport is limited to local/loopback use, and that any non-local exposure requires
  transport encryption or a trusted reverse proxy (Phase 2).
- **FR-017**: The following capabilities MUST be recorded as out of scope for this phase and
  documented as the Phase 2 evolution: delegated authorization (OAuth 2.0), custom API keys,
  per-tool role-based access control beyond the existing guardrail classification, external
  single sign-on/directory federation beyond the existing directory, and corporate transport
  encryption/reverse proxy.
- **FR-018**: When setup is invoked without an explicit mode, the gateway MUST provision
  secured mode; demo mode MUST require an explicit opt-in.
- **FR-019**: The gateway MUST record denied authentication and denied entitlement attempts in
  the audit trail, including the outcome, the time, and the caller identity claim when one was
  presented, and MUST NOT record the credential itself.
- **FR-020**: In secured mode, the gateway MUST return a 401 response for a missing or invalid
  credential and a 403 response for a valid caller who lacks the gateway entitlement.
- **FR-021**: In secured mode, the gateway MUST re-evaluate the caller's entitlement on every
  tool request, including requests made within an already-open session.

### Key Entities *(include if data involved)*

- **Caller identity**: The authenticated person behind a connection, derived from the
  credential presented by the agent client; the unit to which entitlement is granted and to
  which invocations are attributed.
- **Gateway entitlement**: The named access right that authorizes use of the gateway endpoint;
  granted to roles, which are in turn assigned to users or groups. Distinct from the role that
  carries it.
- **Access role**: A named collection of entitlements and data permissions; the thing granted
  to a user. The gateway's role carries the gateway entitlement and the minimum data
  permissions needed by exposed tools.
- **Endpoint protection**: The configuration on the gateway's published endpoint that selects
  the authentication scheme and the required entitlement for secured mode, and the open
  behavior for demo mode.
- **Invocation record**: The audit entry for one tool call, carrying the caller identity,
  status, result, and timing.
- **Access decision record**: The audit entry for an authentication or entitlement decision
  that did not reach a tool, carrying the outcome, time, and any caller identity claim
  presented; it never contains the credential.
- **Gateway connection configuration**: The client-side and gateway-side settings that
  determine where the caller's credential comes from and whether anonymous connections are
  permitted.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In secured mode, 100% of connections without a credential or with an invalid
  credential are refused, with zero tool executions resulting from them.
- **SC-002**: In secured mode, 100% of authenticated users without the entitlement are denied
  before any tool catalog or result is returned.
- **SC-003**: For any two distinct authenticated users, 100% of their invocations are recorded
  under the correct distinct identity, verified across at least 20 interleaved calls.
- **SC-004**: Re-running setup in the same mode produces zero duplicate entitlements and zero
  observable change in access behavior across at least three consecutive runs.
- **SC-005**: A newly entitled user can go from credential issuance to a successful tool
  invocation in under 5 minutes of operator effort, with no gateway code change.
- **SC-006**: Zero caller credentials appear in logs, invocation records, or error responses
  across an authentication test suite that includes failed logins.
- **SC-007**: In secured mode, an entitled user completes a representative read-only call and
  a representative write call with a 100% success rate, and the recorded caller identity
  matches the credential used.
- **SC-008**: Switching modes via setup changes the endpoint's observable authentication
  behavior in 100% of attempts, in both directions (demo to secured and secured to demo).
- **SC-009**: In 100% of fresh environments where setup is run without an explicit mode,
  unauthenticated calls are refused, confirming secured mode was provisioned by default.
- **SC-010**: 100% of denied authentication and denied entitlement attempts appear in the
  audit trail with outcome and time, and 0% of those records contain a credential.
- **SC-011**: In secured mode, 100% of missing or invalid credential attempts return 401 and
  100% of valid callers without the entitlement return 403.
- **SC-012**: In 100% of secured-mode setup or startup attempts with a static backend
  credential present on the tool-invocation path, the attempt fails with an error that names
  the offending setting, and no caller traffic is served under a shared identity.
- **SC-013**: After an entitlement is revoked, 100% of that user's subsequent tool requests
  are denied, including requests made within an already-open session, with no reconnect and
  no gateway configuration change.

## Assumptions

- The organization already operates an IRIS user directory with password authentication
  enabled at the system level; this feature does not change system-wide authentication
  settings.
- Corporate users and their credentials are managed by the directory administrator or an
  external directory; the gateway does not create or manage end-user accounts. Demo users are
  created by the demo bootstrap, not by the packaged module.
- The gateway's agent bridge forwards the client's authorization header unchanged to the
  published endpoint; this behavior is assumed to hold and is validated by the acceptance
  scenarios rather than changed by this feature.
- Phase 1 targets local/loopback HTTP for demonstration; transport encryption for non-local
  exposure is deferred to Phase 2 as stated in FR-016 and FR-017.
- The gateway entitlement is granted through a role, and users may also reach the gateway
  through other roles that carry the same entitlement; the gateway does not enumerate roles.
- The existing tool guardrail classification (read-only, write, critical) remains the
  per-tool authorization mechanism in this phase; per-tool role checks are Phase 2.
- Existing exposed tools keep their current names, parameters, and responses; this feature
  changes who may call them and how calls are attributed, not what they do.
- The demo environment is expected to run in secured mode with test users to prove the
  behavior, while retaining demo mode for offline/local experimentation.
