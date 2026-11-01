# Contract: MCP HTTP Authentication and Authorization

**Feature**: `002-mcp-gateway-auth` | **Date**: 2026-10-25

Agent-facing security contract for the `/mcp/interopmcp` endpoint reached through
`iris-mcp-server` (HTTP transport).

## End-to-end flow

```text
opencode / MCP client
  Authorization: Basic base64(username:password)
        │
        ▼
iris-mcp-server (:8080, config_http.toml)
  allow_anonymous = false
  endpoint has no username/password
  forwards Authorization unchanged
        │
        ▼
IRIS CSP application /mcp/interopmcp (Type 18)
  AutheEnabled = 32 (Password)
  Resource = ""              (service enforces the entitlement)
  MatchRoles = ""            (no role grant)
        │
        ▼
br.musketeers.InteropMCP.MCPService
  Parameter RESOURCE = "InteropMCP_Access"
  AccessCheck -> 403 if the caller lacks USE
  Login       -> JSON 401 on authentication failure
        │
        ▼
Tool dispatch
  Guardrails.CurrentAgent() = $USERNAME (or local-dev in demo)
  Invocations.AgentIdentity = CurrentAgent()
```

## Authentication

### Credential format

- Standard HTTP Basic: `Authorization: Basic <base64(username:password)>`.
- The username is an IRIS user; the password is that user's IRIS password.
- The bridge must not substitute a shared service credential for the caller's credential on
  the tool-invocation path.
- The bridge's `[[iris]] server` credentials are a technical account for the superserver
  connection; they are not the endpoint identity and must not be presented as the caller.

### Success

A valid credential establishes `$USERNAME` and `$ROLES` before the MCP service runs. The
caller may list tools and invoke any tool for which the gateway entitlement and the tool's
own guardrails allow execution.

### Failure

| Condition | HTTP status | Body | Tool execution |
|-----------|-------------|------|----------------|
| No `Authorization` header | `401` | JSON error (`UNAUTHORIZED` / "Authentication required.") | None |
| Invalid username/password | `401` | JSON error (`UNAUTHORIZED` / "Authentication required.") | None |
| Expired/rotated credential | `401` on the next request | JSON error | None |
| Valid user without `InteropMCP_Access` | `403` | Framework denial (no catalog/result) | None |

The response must not reveal whether the username exists, which entitlement is missing, or
which roles other users hold.

## Authorization

### Entitlement

- The required entitlement is the IRIS resource `InteropMCP_Access`.
- It is enforced by `%AI.MCP.Service` through `Parameter RESOURCE` on **every** request.
- The web application's `Resource` property is empty in this phase; the service-level check is
  the primary gate and the only one that can produce the gateway's 403 + audit record.
- A user may hold the entitlement through `InteropMCPRoles` or any other role that carries the
  resource. The gateway does not enumerate roles.

### Per-request re-evaluation

- Every HTTP tool request is a new CSP request; `AccessCheck` runs each time.
- Revoking the role/resource takes effect on the next request, including within an already-open
  HTTP session, with no gateway restart and no reconnect.
- An in-flight call is not retroactively aborted.

### Demo mode

- `AutheEnabled=64`, no caller authentication, `MatchRoles=":%All"`.
- Invocations are attributed to `local-dev`, never `"agent"` or `UnknownUser`.
- Demo mode is never the default; it requires an explicit `dev`/`demo` setup.

## Identity propagation

- `Guardrails.CurrentAgent()` returns `$USERNAME` in secured mode and `local-dev` in demo
  mode (or when `$USERNAME` is empty/`UnknownUser`).
- The generated tool methods pass `CurrentAgent()` to both `Guardrails.Check` and
  `Invoker.Invoke`.
- `Invocations.AgentIdentity` stores that value; `GetInvocationStatus` returns it.
- Two concurrent users must never share an identity; no session state may carry one user's
  identity into another user's request.

## Audit contract

| Attempt | Record |
|---------|--------|
| Successful invocation | `Invocations` row with `AgentIdentity`, tool, status, result, timestamps. |
| Invalid password | IRIS `%SYS.Audit` `%LOGIN` / `LoginFailure` with attempted username, app path, timestamp. |
| Missing/unparseable credential | `%SYS.Audit` `INTEROPMCP` / `AuthenticationDenied` with username claim (if any), endpoint, outcome, timestamp. |
| Valid user without entitlement | `%SYS.Audit` `INTEROPMCP` / `AccessDenied` with authenticated `$USERNAME`, endpoint, outcome, timestamp. |

**Credential exclusion**: No audit row, invocation row, log line, or error response may
contain the `Authorization` header value, the Basic token, or the password. The audit record
may contain the username claim only.

**Audit availability**: `Security.System.AuditEnabled` must be true in secured mode; setup
fails otherwise. Audit write failures do not change the 401/403 response.

## Bridge requirements

`config_http.toml`:

```toml
[[iris]]
name = "local"
server = { host = "localhost", port = 1972, username = "<technical>", password = "<technical>" }
endpoints = [
    { path = "/mcp/interopmcp" }
]

[mcp]
transport = "http"
port = 8080
host = "0.0.0.0"
allow_anonymous = false
```

- No `username`/`password` in `endpoints`.
- `allow_anonymous = false` in secured mode.
- `host = "0.0.0.0"` inside the container is required for Docker port publishing; the host
  publication is loopback-only.
- Startup fails if the mode and `allow_anonymous` disagree, or if a secured endpoint defines
  static credentials.

`opencode.json` (per user):

```json
"InteropMCP": {
  "type": "remote",
  "url": "http://localhost:8080/mcp/interopmcp",
  "headers": { "Authorization": "{env:INTEROPMCP_BASIC}" },
  "enabled": true
}
```

`INTEROPMCP_BASIC` is `base64(username:password)`. It is supplied by the user's environment
and never committed.

## Acceptance matrix

| Scenario | Expected |
|----------|----------|
| Secured, no credential | 401, no tool execution, audit attempt |
| Secured, wrong password | 401, no tool execution, `%LOGIN` LoginFailure |
| Secured, valid user without entitlement | 403, no catalog/result, `AccessDenied` audit |
| Secured, entitled user, readonly tool | Success; `AgentIdentity` = user |
| Secured, entitled user, write tool | Success subject to tool guardrails; identity recorded |
| Two entitled users, interleaved calls | Distinct identities, no bleed |
| Entitlement revoked mid-session | Next request 403; no reconnect |
| Demo, no credential | Success; `AgentIdentity` = `local-dev` |
| Secured config with endpoint `username`/`password` | Startup fails, naming the setting |
| Secured config with `allow_anonymous=true` | Startup fails, naming the setting |

## Out of scope (Phase 2)

OAuth 2.0, custom API keys, per-tool role-based access control beyond the existing
readonly/write/critical guardrails, external LDAP/SSO federation, corporate TLS/reverse proxy,
and WebSocket denial auditing.
