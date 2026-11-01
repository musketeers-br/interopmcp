# Phase 0 Research: Per-User Authentication and Authorization

**Feature**: `002-mcp-gateway-auth` | **Date**: 2026-10-25

This document records the decisions that shape the implementation and the evidence behind
them. It resolves the open questions from the specification and the source document
[`docs/interop-mcp/authentication.md`](../../docs/interop-mcp/authentication.md).

## R1 — Where the entitlement is enforced

**Decision**: Enforce `InteropMCP_Access` in the MCP service class through
`Parameter RESOURCE = "InteropMCP_Access"` and an `AccessCheck` override that records
denials. Leave the web application's `Resource` property empty.

**Why**: The clarified specification requires a 403 for an authenticated user who lacks the
entitlement and requires the gateway to record that denial. The CSP dispatcher evaluates an
application-level `Resource` before the service is reached. In the tested configurations that
denial is surfaced as a login/401 response, not a 403, and the service never runs, so it
cannot write a gateway audit record. The service-level `RESOURCE` check runs after CSP
authentication, produces the required 403, and gives the gateway a place to record the
decision.

**Evidence**:

- `/api/atelier` is provisioned with `AutheEnabled=32`, `Resource=%Development`, confirming
  that Password authentication is bit 5 (`32`) on this instance.
- A temporary Type 2 web application at `/tmp/sec` with `AutheEnabled=32` and
  `Resource=InteropMCP_Access` returned a login page (HTTP 200) for a valid user without the
  resource, not 403.
- A temporary Type 2 web application at `/tmp/mcp2` dispatching to a subclass of
  `%AI.MCP.Service` with `Parameter RESOURCE = "InteropMCP_Access"` and no application
  `Resource` returned **403** for a valid user without the entitlement (`tmpno`), and allowed
  an entitled user (`tmpmcp`) through to the gateway-origin check (502
  `GATEWAY_REQUIRED`, as expected without the bridge header).
- `%AI.MCP.Service` documents `OnPreDispatch` as `Final` and `AccessCheck` as overridable.
  The subclass override `##super(.pAuthorized)` compiled to
  `##class(%AI.MCP.Service)$this.AccessCheck` and used the subclass `RESOURCE` correctly.

**Trade-off**: The web application is not itself restricted by a `Resource`; an authenticated
IRIS user can reach the service, where the class denies them. This is the framework's
documented hardening mechanism for `%AI.MCP.Service`. Setup asserts that
`$PARAMETER("br.musketeers.InteropMCP.MCPService","RESOURCE")` is non-empty in secured mode,
so the gate cannot be lost silently. The application `Resource` remains an optional
deployment hardening for environments that accept platform-level denial semantics and do not
need the gateway audit record.

**Alternatives rejected**:

- Application `Resource` only: no gateway audit, and the tested denial is not 403.
- Both layers: the application layer preempts the service, so the gateway never sees the
  denial. Defense in depth is preserved at the service parameter and the setup assertion.
- Override `%IsAuthorized`: it is marked `Internal`, and the class documentation names
  `OnAuthenticate` as the supported extension point. `AccessCheck` is public and not Final.

## R2 — Audit of authentication and entitlement denials

**Decision**: Use two audit planes, both queryable through `%SYS.Audit`:

1. **Authentication failures** — IRIS records invalid credentials as `%LOGIN` /
   `LoginFailure`, including the attempted username, the application path, and the timestamp.
   Missing credentials are not recorded by IRIS, so `MCPService.Login` is overridden to write
   an `INTEROPMCP` / `AuthenticationDenied` event before delegating to the base JSON 401.
2. **Entitlement denials** — `MCPService.AccessCheck` writes an `INTEROPMCP` /
   `AccessDenied` event through `%SYS.Audit.WriteToAuditFile` with the authenticated
   `$USERNAME`, the endpoint, the outcome, and the timestamp. No credential is written.

**Why not a new persistent class**: The denied user may not have write access to the gateway
database (that is the point of least privilege), so a gateway-owned persistent record would
fail exactly when it is needed. `%SYS.Audit.WriteToAuditFile` works without gateway database
write and populates the audit row's `Username` column from `$USERNAME`.

**Evidence**:

- `%SYS.Audit` already contains `%LOGIN` rows with `Event=LoginFailure`, a populated
  `Username` (e.g. `tmpmcp`, `tmpno`), and descriptions naming the failing application
  (`/tmp/mcp2 login failure`).
- A temporary audit call as `tmpaudit` (a user with only code read and no gateway data write)
  returned `AUDIT=1`; the resulting `TEST` rows had `Username=tmpaudit`, `EventData=user=...`,
  and a timestamp.
- A no-credential request to a Type 2 test application produced no `%LOGIN` row, confirming
  the need for the `Login` override.

**Invariants**:

- The audit record never contains the `Authorization` header value or the password.
- The username claim is parsed from the Basic header only for the record; the credential is
  discarded.
- If the audit sink fails, the request still returns the correct 401/403; the failure is
  reported through the gateway log (best effort) and does not turn into a 500.
- `Security.System.AuditEnabled` must be true in secured mode; setup fails with an actionable
  error if it is not.

**Alternative rejected**: Recording denials only in `^InteropMCP.LogD`. It is not reliably
writable by a user who lacks the gateway role, and it is not the platform audit trail.

## R3 — `CurrentAgent()` and the local development identity

**Decision**: `Guardrails.CurrentAgent()` returns:

- `local-dev` when the provisioned mode is demo (`dev`/`demo`), or when `$USERNAME` is empty
  or `UnknownUser`;
- `$USERNAME` otherwise (secured mode).

`Setup.Run` persists the selected mode in `^InteropMCP.Config("mode")` so the runtime does not
have to infer it from `$USERNAME` alone.

**Why**: In an unauthenticated CSP application (`AutheEnabled=64`), `$USERNAME` is
`UnknownUser`. The specification requires a clearly labeled local development identity, not a
generic placeholder. Persisting the mode is deterministic and survives `$USERNAME` quirks.
In a secured application (`AutheEnabled=32`), the CSP dispatcher establishes the real
`$USERNAME` before dispatch; the fallback only covers a misconfigured or unauthenticated
request.

**Evidence**:

- A temporary CSP page in an `AutheEnabled=64` application returned
  `USERNAME=UnknownUser`, `ROLES=%All` with `MatchRoles=":%All"`.
- The same page in an `AutheEnabled=32` application with a valid Basic credential returned
  `USERNAME=tmpmcp`, `ROLES=TempMCPRole`.
- `%AI.MCP.Service` documents that the CSP dispatcher imports the security context before
  Page dispatch, so `$USERNAME`/`$ROLES` are already established when `OnAuthenticate` and
  the tool dispatch run.

**Alternative rejected**: Returning `$USERNAME` unconditionally. It would attribute demo
calls to `UnknownUser`, which the spec explicitly rejects as a generic placeholder.

## R4 — Secured endpoint configuration

**Decision**: In secured mode, provision the Type 18 application with:

```text
AutheEnabled = 32        # Password (bit 5)
Resource     = ""        # entitlement enforced by the service class (R1)
MatchRoles   = ""        # do not grant roles
LoginPage    = ""        # JSON 401 via Login(), not an HTML login page
NameSpace    = target namespace
DispatchClass = br.musketeers.InteropMCP.MCPService
Type         = 18
```

In demo mode: `AutheEnabled=64`, `Resource=""`, `MatchRoles=":%All"`, `LoginPage=""`.

**Why**: `AutheEnabled=1` is Kerberos CCache, not Password. `MatchRoles` grants roles to the
session; it does not restrict access. `AutheEnabled=32` is the value used by the working
`/api/atelier` application on this instance and by the source document.

**Evidence**: `/api/atelier` (`AutheEnabled=32`) authenticates a Basic user; a temporary
application with `AutheEnabled=32` authenticated `tmpmcp` and returned the expected identity.

**Alternative rejected**: `AutheEnabled=1` (current production branch) — unusable for Basic
and contrary to the source document.

## R5 — Bridge forwarding and the static-credential ban

**Decision**:

- `config_http.toml`: `allow_anonymous = false`; `endpoints` contain only `path`; no
  `username`/`password` on the endpoint.
- Keep the `[[iris]] server` technical credentials; they authenticate the bridge to the IRIS
  superserver and are not the endpoint identity.
- Add `scripts/validate-mcp-config.py` and run it from `mcp-launcher` before starting
  `iris-mcp-server`. It fails with an actionable message when secured mode and
  `allow_anonymous=true` are combined, when demo mode and `allow_anonymous=false` are
  combined, or when an endpoint defines `username`/`password` in secured mode.
- Validate the actual forwarding behavior with an integration test that sends two different
  Basic credentials through the bridge and observes two distinct `AgentIdentity` values.

**Why**: The bridge documentation and binary strings state that any `Authorization` header is
forwarded as-is to the MCP service and that endpoint `username`/`password` would replace the
caller's header. A static endpoint credential collapses all users into one identity, which
the specification forbids (FR-014). The bridge configuration is outside IRIS, so the startup
validator is the enforcement point; IRIS setup enforces the complementary invariant (the
service `RESOURCE` is present).

**Evidence**: `iris-mcp-server` strings include `allow_anonymous`, `forward_headers`,
`endpoints` (`path`, `username`, `password`, `bearer`), and messages describing the
forwarding behavior. The skill reference documents the two-layer model. The actual bridge
round-trip is a Phase E validation task because the Type 18 application is not directly
reachable over ordinary HTTP in the test environment (direct requests returned 404/web
gateway errors).

**Alternative rejected**: Relying on the bridge to reject a static endpoint credential. Its
behavior is not part of the gateway code and is not guaranteed across versions; an explicit
pre-start check makes the failure deterministic and names the offending setting.

## R6 — Transport and port exposure

**Decision**: The bridge binds `0.0.0.0` inside the container (required for Docker port
publishing), but `docker-compose.yml` publishes the IRIS and bridge ports on host loopback
only:

```yaml
ports:
  - "127.0.0.1:1972:1972"
  - "127.0.0.1:52773:52773"
  - "127.0.0.1:8080:8080"
```

Secured mode over non-loopback HTTP is unsupported until TLS or a trusted reverse proxy is
added (Phase 2). The documentation states this explicitly.

**Why**: Binding the bridge to `127.0.0.1` inside the container would make the Docker port
mapping unreachable. Loopback publication at the host boundary is the practical equivalent
for local development and satisfies the Phase 1 constraint.

**Alternative rejected**: Binding the bridge to `127.0.0.1` inside the container and mapping
the port — the published port would not reach the bridge.

## R7 — Minimum role permissions

**Decision**: `InteropMCPRoles` carries:

```text
InteropMCP_Access:U
%DB_IRISAPP_CODE:R
%DB_IRISAPP_DATA:RW
%DB_IRISLIB:R
%DB_IRISTEMP:RW
%Service_SQL:U
```

The exact database resource names are environment-specific; the setup code uses the resources
present on the target instance and documents the mapping. Production deployments should
replace the demo database grants with the minimum required by their exposed tools.

**Why**: The service must load its own compiled code, read the catalog, write invocations and
approvals, use embedded SQL, and load system routines. The temporary role with this set ran a
CSP page as `tmpmcp` and wrote an audit record successfully. The MCP tool path may require
additional grants; the integration tests in Phase E will identify any missing permission and
the setup will be adjusted to the smallest working set.

**Alternative rejected**: Granting `%All` or `%Developer` — violates least privilege and
would let every gateway user reach unrelated data.

## R8 — Demo users and credentials

**Decision**: The demo bootstrap creates/reconciles `mcp_demo` and `mcp_demo2` with
`InteropMCPRoles`. The password comes from the environment
(`INTEROPMCP_DEMO_PASSWORD`); the bootstrap fails with an actionable message if it is
missing. The Basic header value is derived locally and never committed. `opencode.json` uses
`{env:INTEROPMCP_BASIC}`.

**Why**: The specification says demo users are created by the demo bootstrap, not the IPM
module, and that credentials must not appear in records or the repository. An environment
variable keeps the secret out of source control while allowing the demo to run secured.

**Alternative rejected**: Hard-coding `mcp_demo`/`demo` in `opencode.json` or the bootstrap.
It would commit a credential and make the secured default indistinguishable from a shared
demo secret.

**Client-side sync pitfall**: `{env:INTEROPMCP_BASIC}` is interpolated from the environment of
the process that launches OpenCode. Renaming or changing the variable in `opencode.json`
without updating the operator's shell startup (`~/.bashrc`) and `.env*` leaves the client
unauthenticated (401, "Failed to get tools"). A rebuild cannot fix it: `~/.bashrc` and `.env`
live outside the image. All four carriers — `opencode.json`, `.env.example`, `.env`, and the
launch shell — must change together, followed by a restart from a new shell.

## R9 — Identity propagation into invocations and status

**Decision**: `Registry.GenerateToolsClass()` emits
`##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent()` in both the guardrail and
invoker calls. `GeneratedTools.cls` is regenerated. `InvocationStatusTools` adds
`AgentIdentity` to its ROWSPEC and SELECT so callers and auditors can see the identity through
the status tool.

**Why**: The current generated code passes the literal `"agent"`, which makes every
invocation anonymous. The specification requires the authenticated identity for every
invocation and its exposure through status reporting.

**Evidence**: `Registry.cls` currently emits `"agent"` in both calls; `Invocations` already
has `AgentIdentity`; the status query currently selects only `InvocationId`, `Status`, and
`Result`.

## R10 — Validation and acceptance evidence

The following are the planned proofs for the specification's success criteria:

| Criterion | Proof |
|-----------|-------|
| SC-001 / SC-011 (401) | HTTP tests with no credential and a wrong password against the bridge; assert 401 and zero tool executions. |
| SC-002 / SC-011 (403) | HTTP test with a valid user without `InteropMCP_Access`; assert 403 before any catalog/result. |
| SC-003 (identity) | Two users, at least 20 interleaved calls; assert distinct `AgentIdentity` values and no bleed. |
| SC-004 (idempotency) | Three consecutive secured setups; assert one resource, one role, and unchanged behavior. |
| SC-005 (onboarding) | Create a user, grant the role, connect, invoke; measure operator steps. |
| SC-006 (no credentials) | Scan logs, `Invocations`, `%SYS.Audit`, and error responses for the test passwords/headers. |
| SC-007 (read/write) | Entitled user calls `PayLookup` and `CustomerUpdate`; assert success and matching identity. |
| SC-008 (mode switch) | Setup demo → secured → demo; assert observable auth behavior changes each time. |
| SC-009 (default) | Fresh setup with no mode; assert unauthenticated calls are refused. |
| SC-010 (denial audit) | Query `%SYS.Audit` for `LoginFailure`, `AuthenticationDenied`, and `AccessDenied`; assert outcome/time/username and no credential. |
| SC-012 (static credential) | Run the startup validator with an endpoint `username`/`password`; assert failure naming the setting. |
| SC-013 (revocation) | Remove the role/resource from an active user; assert the next request is 403 without reconnect. |

## Open validation items (resolved during implementation)

1. Confirm the exact HTTP status/body produced by the Type 18 application through
   `iris-mcp-server` for missing/invalid credentials (expected 401 JSON from `Login()`), for
   no entitlement (expected 403 from `AccessCheck`), and for an entitled user (200).
2. Confirm `Login()` is invoked on the Type 18/bridge path for missing credentials; if not,
   record the missing-credential denial from the earliest available hook and document the
   residual gap.
3. Confirm the minimum role grants needed by the actual tool path (the R7 set is the starting
   point; adjust to the smallest working set).
4. Confirm that the custom `INTEROPMCP` audit event type is visible/queryable in the target
   IRIS version and that `Force=1` writes even when the event type is not explicitly enabled.
5. Confirm the bridge forwards `Authorization` unchanged when `allow_anonymous=false` and no
   endpoint credential is configured, using two distinct users.
6. Confirm the WebSocket transport is out of scope for Phase 1 (the bridge uses HTTP); note
   that the class-level `RESOURCE` still enforces access for WebSocket, but denial auditing is
   a Phase 2 follow-up.
