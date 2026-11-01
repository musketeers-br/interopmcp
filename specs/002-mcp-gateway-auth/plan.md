# Implementation Plan: Per-User Authentication and Authorization for the MCP Gateway

**Branch**: `002-mcp-gateway-auth` | **Date**: 2026-10-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-mcp-gateway-auth/spec.md`

## Summary

Turn the InteropMCP gateway from an open demo endpoint into a per-user, least-privilege
service. Each agent client presents its own IRIS Basic credential; `iris-mcp-server` forwards
that `Authorization` header unchanged; the Type 18 web application authenticates the caller
with `AutheEnabled=32` (Password); and `%AI.MCP.Service` enforces the
`InteropMCP_Access` entitlement on every request through `Parameter RESOURCE`. The gateway
records the authenticated `$USERNAME` as the invocation identity, records entitlement denials
in the IRIS audit trail, and provisions the resource, role, and endpoint idempotently with
secured mode as the default. Demo mode remains available only as an explicit opt-in.

The design deliberately keeps the web application's `Resource` empty and enforces the
entitlement in the service class. This is the only arrangement that satisfies the clarified
401/403 split and the gateway-side denial audit: an application-level `Resource` denial is
handled by the CSP dispatcher before the service, produces a login/401 response in the
configurations tested, and cannot be recorded by the gateway. See
[research.md](research.md) for the evidence and the trade-off.

## Technical Context

**Language/Version**: ObjectScript (IRIS 2026.3 AI HUB), TOML configuration, JSON
(`opencode.json`), Python 3.11+ for the startup configuration validator and smoke harness.

**Primary Dependencies**: InterSystems IRIS 2026.3, `%AI.MCP.Service`, `%AI.ToolSet`,
`iris-mcp-server` (HTTP transport), `Security.Applications`, `Security.Resources`,
`Security.Roles`, `Security.Users`, `%SYS.Audit`, Docker Compose.

**Storage**: Existing IRIS globals `^InteropMCP.InvocationsD/I/S`,
`^InteropMCP.ApprovalsD`, `^InteropMCP.LogD`, `^InteropMCP.Catalog`; platform audit
`%SYS.Audit`. No new persistent class is required: the "Access decision record" is realized
as a `%SYS.Audit` event (`EventType=INTEROPMCP`, `Event=AccessDenied` /
`AuthenticationDenied`) with the authenticated username, outcome, endpoint, and timestamp.

**Testing**: `%UnitTest` suites under `tests/br/musketeers/InteropMCP/` for setup,
`CurrentAgent()`, and access-decision recording; Python HTTP integration tests for 401/403,
header forwarding, and identity isolation; the existing Python smoke harness extended with
Basic credentials; container-level validation through `docker compose`.

**Target Platform**: Linux container (IRIS Community 2026.3 AI HUB) with the
`iris-mcp-server` bridge; local/loopback HTTP for Phase 1.

**Project Type**: Single IRIS application package with a containerized sidecar bridge and
developer tooling.

**Performance Goals**: Authentication and authorization add no more than one resource check
per request; the existing interactive tool-call latency budget (30 s wait window) is
unchanged. Setup remains idempotent and completes in seconds.

**Constraints**: No caller credential may be written to logs, invocation records, or error
responses. Secured mode must not carry a static endpoint credential. The bridge must forward
the caller's `Authorization` header unchanged. The gateway must not create or manage
corporate users. The client credential must stay in sync across `opencode.json`, `.env.example`,
`.env`, and the launch shell (`~/.bashrc`); a container rebuild does not update the latter two.
Phase 1 is HTTP loopback only; non-local exposure requires TLS or a trusted reverse proxy
(Phase 2).

**Scale/Scope**: One gateway endpoint, one entitlement resource, one access role, four demo
tools, two demo users. The design applies to any number of IRIS users and any number of
exposed tools without code changes.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| Container-Oriented Architecture | All changes deploy through the existing Docker image/compose stack; no host-specific paths beyond the existing bind mount. | PASS |
| Comprehensive Logging | Authentication/authorization outcomes are written to the platform audit log; invocation identity is persisted; no credentials are logged. | PASS |
| Monitoring and Observability | The existing health snapshot remains; denial audit records and invocation identity are queryable; the bridge's `auth_rejections_total` metric is documented. | PASS |
| Security by Design | Per-user authentication, least-privilege entitlement, 401/403 semantics, no static endpoint credential, audit of denials, setup validation. | PASS |
| Technology Stack | ObjectScript for IRIS logic; Python only for the startup validator and tests; no frontend work. | PASS |

**Post-design re-check**: PASS. Phase 1 artifacts (`data-model.md`, `contracts/*`, and
`quickstart.md`) were reviewed against the six principles and introduce no new stack,
service, or persistent class. No constitutional violations or justified exceptions. The
design increases security coverage; a security review is required for the provisioning and
audit changes, as mandated by the constitution.

## Project Structure

### Documentation (this feature)

```text
specs/002-mcp-gateway-auth/
├── plan.md              # This file
├── research.md          # Phase 0 decisions and evidence
├── data-model.md        # Phase 1 entities and rules
├── quickstart.md        # Phase 1 validation guide
├── contracts/
│   ├── admin-api.md     # Setup / provisioning / audit class contracts
│   ├── mcp-auth.md      # HTTP authentication and authorization contract
│   └── config.md        # TOML / JSON configuration contract
├── checklists/
│   └── requirements.md  # 16/16 passing (unchanged)
└── tasks.md             # Phase 2 output (/speckit.tasks — not created here)
```

### Source Code (repository root)

```text
src/br/musketeers/InteropMCP/
├── Setup.cls                    # Run(pMode="prod"), EnsureSecurity(), mode-aware app provisioning
├── MCPService.cls               # Parameter RESOURCE, AccessCheck/Login audit overrides
├── Guardrails.cls               # CurrentAgent() and identity propagation
├── Registry.cls                 # GeneratedTools emits CurrentAgent() instead of "agent"
├── GeneratedTools.cls           # Regenerated; never hand-edited
├── InvocationStatusTools.cls    # ROWSPEC includes AgentIdentity
├── Invocations.cls              # AgentIdentity documentation/semantics
├── Log.cls                      # Structured gateway log (best-effort for denials)
└── Demo/Setup.cls               # Demo production unchanged

config_http.toml                 # allow_anonymous=false, no endpoint credentials
config_stdio.toml                # Unchanged (stdio is not the secured HTTP path)
docker-compose.yml               # Loopback-published ports; mode/credential env wiring
opencode.json                    # Per-user Authorization header via {env:INTEROPMCP_BASIC}
iris.script                      # Run("prod") for the container build
bootstrap-gateway.script         # Secured demo users + Run("prod")
.env.example                     # Documented demo/bridge variables (no real secrets)

scripts/
└── validate-mcp-config.py       # Startup validator: mode vs allow_anonymous vs endpoint creds

tests/br/musketeers/InteropMCP/
├── TestAuthProvisioning.cls     # Resource/role/app idempotency and mode switching
├── TestCurrentAgent.cls         # $USERNAME / local-dev semantics
└── TestAccessDecision.cls       # Audit record fields and credential exclusion

python/smoke/
└── mcp_client.py                # Extended with --basic / INTEROPMCP_BASIC
```

**Structure Decision**: Single project rooted at the existing IRIS package. The only new
source directory is `scripts/` for the pre-start configuration validator. No new service,
module, or frontend is introduced. The generated tools class remains a build artifact of
`Registry.GenerateToolsClass()`.

## Phase 0 / Phase 1 Outputs

- [research.md](research.md): audit-vs-enforcement ordering, `$USERNAME` semantics,
  `AutheEnabled=32`, class `RESOURCE` vs application `Resource`, bridge forwarding, audit
  sink, and the startup validator.
- [data-model.md](data-model.md): caller identity, entitlement, access role, endpoint
  protection, invocation record, access decision record, and connection configuration.
- [contracts/admin-api.md](contracts/admin-api.md): `Setup.Run`, `EnsureSecurity`,
  `Guardrails.CurrentAgent`, `InvocationStatusTools`, and the audit record contract.
- [contracts/mcp-auth.md](contracts/mcp-auth.md): Basic authentication, 401/403 semantics,
  per-request entitlement, identity propagation, and credential-handling invariants.
- [contracts/config.md](contracts/config.md): `config_http.toml`, `opencode.json`,
  `docker-compose.yml`, and environment-variable contract.
- [quickstart.md](quickstart.md): secured setup, demo users, client configuration, and
  end-to-end validation scenarios.

## Implementation Phases

### Phase A — Provisioning and endpoint configuration

1. `Setup.EnsureSecurity()`: create/reconcile `InteropMCP_Access` (Type 9, no public
   permission), `InteropMCPRoles` (resource `InteropMCP_Access:U` plus the minimum database
   and SQL grants), and verify `Security.System.AuditEnabled`.
2. `Setup.Run(pMode="prod")`: validate the mode explicitly (`prod`/`secured` vs
   `dev`/`demo`), assert `$PARAMETER("...MCPService","RESOURCE")` is non-empty in secured
   mode, and create/modify the Type 18 application with:
   - secured: `AutheEnabled=32`, `Resource=""`, `MatchRoles=""`, `LoginPage=""`;
   - demo: `AutheEnabled=64`, `Resource=""`, `MatchRoles=":%All"`, `LoginPage=""`.
3. Make resource/role/app provisioning idempotent (`Exists` + `Modify`, or `Create` when
   absent). Re-running setup must not duplicate or downgrade definitions.
4. Update `iris.script` and `bootstrap-gateway.script` to run secured mode by default. The demo
   bootstrap creates/reconciles `mcp_demo` and `mcp_demo2` with `InteropMCPRoles`, using a
   password supplied through the environment; it never commits the password.

### Phase B — Service enforcement and audit

1. `MCPService.Parameter RESOURCE = "InteropMCP_Access"`.
2. Override `AccessCheck` to call `##super(.pAuthorized)` and, when `pAuthorized=0`, write an
   `INTEROPMCP` / `AccessDenied` audit event with `$USERNAME`, endpoint, and outcome. Return
   the base status so the framework emits 403.
3. Override `Login` to write an `INTEROPMCP` / `AuthenticationDenied` audit event (username
   claim parsed from the `Authorization` header when present, never the credential), then
   delegate to `##super(skipheader)` for the JSON 401. IRIS continues to record invalid
   credentials as `%LOGIN` / `LoginFailure`.
4. Ensure the audit helper catches and logs sink failures without turning a denial into a 500,
   and never includes the credential or the full header value.

### Phase C — Identity propagation

1. `Guardrails.CurrentAgent()`: return `$USERNAME` when it is a real authenticated identity;
   return `local-dev` in demo mode or when `$USERNAME` is empty/`UnknownUser`.
2. `Registry.GenerateToolsClass()` emits `##class(Guardrails).CurrentAgent()` for both
   `Guardrails.Check` and `Invoker.Invoke`; regenerate `GeneratedTools.cls`.
3. Extend `InvocationStatusTools.GetInvocationStatus` ROWSPEC/SELECT with `AgentIdentity`.
4. Add the identity to the invocation/audit documentation and ensure no code path still passes
   the literal `"agent"`.

### Phase D — Client, bridge, and deployment configuration

1. `config_http.toml`: `allow_anonymous = false`; no `endpoints[].username/password`; keep
   the `[[iris]] server` technical credentials (environment-substituted where supported).
2. `opencode.json`: add
   `"headers": { "Authorization": "{env:INTEROPMCP_BASIC}" }` to the remote MCP entry.
3. `docker-compose.yml`: publish IRIS and bridge ports on host loopback only
   (`127.0.0.1:...`); pass the operating mode and demo password through the environment.
4. Add `scripts/validate-mcp-config.py` and run it from `mcp-launcher` before starting the
   bridge. It fails with an actionable message when:
   - secured mode is selected and `allow_anonymous` is true;
   - demo mode is selected and `allow_anonymous` is false;
   - any endpoint defines `username` or `password` in secured mode.
5. Document that the bridge binds `0.0.0.0` inside the container only so Docker can publish
   the port; the host publication is loopback. Non-local exposure is unsupported until TLS
   or a trusted reverse proxy is added (Phase 2).

### Phase E — Tests, documentation, and acceptance

1. Unit tests: provisioning idempotency, mode switching, resource/role reconciliation,
   `CurrentAgent()`, audit record fields, and credential exclusion.
2. HTTP integration tests: missing credential → 401, invalid credential → 401, valid user
   without entitlement → 403, entitled user → 200/tool result, revoked entitlement → 403 on
   the next request, two users → distinct `AgentIdentity` values.
3. Bridge tests: verify the client `Authorization` header reaches IRIS unchanged and that no
   endpoint static credential overrides it.
4. Update `docs/interop-mcp/authentication.md`, `architecture.md`, `README.md`,
   `troubleshooting.md`, `quickstart.md`, and correct
   `specs/001-interop-mcp/tasks.md` T042 (`Password = 32`, not `1`).
5. Re-run the Constitution Check and the requirement checklist after implementation.

## Risks and Decisions

| Risk / decision | Resolution |
|-----------------|------------|
| Application `Resource` denies before the service, preventing a gateway 403/audit record | Keep the application `Resource` empty; enforce `InteropMCP_Access` through `%AI.MCP.Service`'s `RESOURCE` and log the denial in `AccessCheck`. Setup asserts the parameter is present. |
| Missing credentials are not recorded by IRIS `%LOGIN` | Override `Login` to write an `AuthenticationDenied` audit event; IRIS continues to record invalid passwords as `LoginFailure`. |
| The denial audit writer runs as the denied user, who may lack gateway database write | Use `%SYS.Audit.WriteToAuditFile` (verified to work without gateway database write) as the authoritative sink; gateway `Log.Write` is best-effort only. |
| The bridge could be configured with a static endpoint credential | Pre-start validator rejects `endpoints[].username/password` in secured mode; setup asserts the IRIS-side `RESOURCE` is present. |
| Re-running setup disrupts live sessions | Reconcile with `Exists` + `Modify` instead of unconditional delete/create; keep behavior identical across runs. |
| WebSocket transport has a separate authorization hook | Phase 1 uses the bridge's HTTP transport; each tool call is a REST request covered by `AccessCheck`. WebSocket denial auditing is documented as a Phase 2 follow-up. |

## Complexity Tracking

No constitutional violations. No additional projects, repositories, or architectural layers
are introduced.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | — | — |

## Definition of Done

- Secured mode is the default; demo mode requires an explicit `dev`/`demo` mode.
- A fresh setup creates `InteropMCP_Access`, `InteropMCPRoles`, and the secured endpoint once;
  three consecutive runs produce no duplicates and no behavior change.
- Missing/invalid credentials → 401; valid user without entitlement → 403; entitled user →
  successful read-only and write tool calls.
- Every invocation records the authenticated `$USERNAME`; demo calls record `local-dev`.
- Every entitlement denial and every authentication failure is queryable in `%SYS.Audit` with
  outcome, time, and username claim, and no record contains a credential.
- Revoking the entitlement denies the user's next request, including within an open HTTP
  session, without a gateway restart or reconnect.
- The startup validator rejects a secured configuration that permits anonymous access or
  carries endpoint credentials.
- All unit/integration tests pass; documentation and the Constitution Check are updated.
