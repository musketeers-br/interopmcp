# Phase 1 Data Model: Per-User Authentication and Authorization

**Feature**: `002-mcp-gateway-auth` | **Date**: 2026-10-25

This feature adds no new persistent class. It adds one entitlement resource, one access role,
two audit event kinds in the platform audit log, and one runtime mode marker. The existing
invocation store gains a defined identity semantic and a status-tool projection.

## Entities

### 1. Caller identity (derived, not separately persisted)

The person behind a request, established by CSP Basic authentication and read as `$USERNAME`.

| Field | Type | Rules |
|-------|------|-------|
| Username | `%String` | The IRIS user authenticated by the CSP dispatcher. Never a shared service account. |
| Roles | `%String` | `$ROLES` for the session; used only for diagnostics and least-privilege validation, never as the gateway's access restriction. |
| Mode | enum `secured` \| `demo` | Read from `^InteropMCP.Config("mode")`. In `demo`, the effective identity is `local-dev` regardless of `$USERNAME`. |

**Derivation**: `Guardrails.CurrentAgent()`:

```text
if mode = "demo"            -> "local-dev"
elseif $USERNAME = ""       -> "local-dev"
elseif $USERNAME = "UnknownUser" -> "local-dev"
else                        -> $USERNAME
```

**Invariants**: The identity is never sourced from a request parameter, a static bridge
credential, or a client-supplied header other than the authenticated `Authorization` header.
It is never written with the credential.

### 2. Gateway entitlement (`InteropMCP_Access`, `Security.Resources`)

The named access right that authorizes use of the gateway endpoint.

| Field | Type | Rules |
|-------|------|-------|
| Name | `%String` | Exactly `InteropMCP_Access`; created once. |
| Description | `%String` | Human-readable purpose (e.g. "InteropMCP gateway access"). |
| PublicPermission | `Security.Datatype.Permission` | Empty; the resource is not public. |
| Type | `Security.Datatype.ResourceType` | `9` (generic resource), matching `%Development` and other application resources on this instance. |

**Lifecycle**: `EnsureSecurity()` creates it if absent and leaves it unchanged if present.
Re-running setup must not duplicate it or alter its public permission.

### 3. Access role (`InteropMCPRoles`, `Security.Roles`)

The role that carries the gateway entitlement plus the minimum permissions the tools need.

| Field | Type | Rules |
|-------|------|-------|
| Name | `%String` | Exactly `InteropMCPRoles`. |
| Description | `%String` | Human-readable purpose. |
| Resources | comma list `Resource:Permission` | Must include `InteropMCP_Access:U` and the minimum database/service grants. Existing unrelated grants are preserved. |
| GrantedRoles | comma list | Not used by this feature; preserved if present. |
| EscalationOnly | `%Boolean` | `0`; the role is assignable to ordinary users. |

**Minimum grant set** (demo instance; production substitutes its own database resources):

```text
InteropMCP_Access:U
%DB_IRISAPP_CODE:R
%DB_IRISAPP_DATA:RW
%DB_IRISLIB:R
%DB_IRISTEMP:RW
%Service_SQL:U
```

**Invariants**: The role must not carry `%All`, `%Developer`, `%Manager`, or unrelated data
grants. The role is the only supported way to grant the entitlement; users may also reach the
endpoint through another role that carries the same resource (the gateway does not enumerate
roles).

### 4. Endpoint protection (`Security.Applications`)

The Type 18 web application at `/mcp/interopmcp`.

| Field | Secured value | Demo value | Rules |
|-------|---------------|------------|-------|
| Type | `18` | `18` | MCP service application. |
| NameSpace | target namespace (e.g. `IRISAPP`) | same | Bound to the gateway namespace. |
| DispatchClass | `br.musketeers.InteropMCP.MCPService` | same | Service class. |
| AutheEnabled | `32` (Password) | `64` (Unauthenticated) | `32` is the only supported Basic-auth setting for Phase 1. |
| Resource | `""` | `""` | The entitlement is enforced by the service class; see research R1. |
| MatchRoles | `""` | `":%All"` | `MatchRoles` grants roles; it never restricts. Empty in secured mode. |
| LoginPage | `""` | `""` | JSON 401 from `Login()` instead of an HTML login page. |
| Enabled | `1` | `1` | Must be enabled. |

**Invariants**:

- The application's `Resource` is never used as the primary entitlement gate in this phase;
  the service `RESOURCE` parameter is.
- `MCPService` must declare `Parameter RESOURCE = "InteropMCP_Access"`. Setup fails secured
  mode if `$PARAMETER("br.musketeers.InteropMCP.MCPService","RESOURCE")` is empty.
- The application is reconciled in place (`Exists` + `Modify`); setup must not duplicate it.

### 5. Runtime mode (`^InteropMCP.Config("mode")`)

| Field | Type | Rules |
|-------|------|-------|
| mode | `%String` enum `secured` \| `demo` | Written by `Setup.Run` after successful provisioning. `CurrentAgent()` reads it. |

**Transitions**: `Setup.Run("prod"|"secured")` → `secured`; `Setup.Run("dev"|"demo")` → `demo`.
Any other mode is rejected with an actionable error (no accidental insecure fallback).

### 6. Invocation record (`br.musketeers.InteropMCP.Invocations`, existing)

One row per tool call, already the gateway audit backbone.

| Field | Type | Rules |
|-------|------|-------|
| InvocationId | `%String` | Unique GUID; returned to the agent. |
| ToolName | `%String` | Published tool name. |
| AgentIdentity | `%String` | `CurrentAgent()` value: authenticated `$USERNAME` or `local-dev`. Never `"agent"`. |
| Parameters | `%String` (JSON) | Validated payload; no credentials. |
| Status | enum | `received` → `executing` → `completed` \| `failed`; `received` → `pending-approval` → `executing` \| `rejected`. |
| Result / ErrorMessage | `%String` | Terminal payload/error; no credentials. |
| MessageHeaderId | `%Integer` | Native trace linkage (0 in the current design). |
| StartedAt / EndedAt | `%TimeStamp` | Creation and last transition. |

**Status-tool projection**: `InvocationStatusTools.GetInvocationStatus` returns
`InvocationId`, `Status`, `Result`, and **`AgentIdentity`** (new column). The row remains
readable by the caller who owns the invocation; no cross-user filtering is added in this
phase (the invocation ID is the bearer reference).

### 7. Access decision record (`%SYS.Audit`, platform audit log)

The audit entry for a decision that did not reach a tool. It is a `%SYS.Audit` row, not a new
gateway table.

| Audit field | Authentication denial | Entitlement denial |
|-------------|----------------------|--------------------|
| EventType | `%LOGIN` (IRIS) or `INTEROPMCP` (missing credential) | `INTEROPMCP` |
| Event | `LoginFailure` or `AuthenticationDenied` | `AccessDenied` |
| EventSource | `%Login` or `InteropMCP` | `InteropMCP` |
| Username | Attempted username when IRIS could parse it; empty otherwise | Authenticated `$USERNAME` |
| Description | Human-readable outcome (never the credential) | Human-readable outcome |
| EventData | `user=<claim>;endpoint=<path>;outcome=authentication-denied` | `user=<name>;endpoint=<path>;outcome=entitlement-denied` |
| UTCTimeStamp | Platform timestamp | Platform timestamp |
| Roles / Namespace / ClientIPAddress | Populated by the platform where available | Populated by the platform where available |

**Invariants**:

- The `Authorization` header, password, and Basic token are never stored.
- The record is written even when the denied user has no gateway database write access.
- A failure to write the record must not change the 401/403 response.
- `%LOGIN` / `LoginFailure` already covers invalid passwords; `AuthenticationDenied` covers
  missing or unparseable credentials. Duplicate records for the same attempt are acceptable
  and are documented.

### 8. Gateway connection configuration (client + bridge)

The settings that determine where the credential comes from and whether anonymous access is
allowed.

| Setting | Location | Secured value | Rules |
|---------|----------|---------------|-------|
| `allow_anonymous` | `config_http.toml` `[mcp]` | `false` | Must match the selected mode. |
| `endpoints[].username` / `password` | `config_http.toml` | absent | Must be absent in secured mode; otherwise startup fails. |
| `server.username` / `password` | `config_http.toml` `[[iris]]` | technical account | Not the endpoint identity; may be environment-substituted. |
| `headers.Authorization` | `opencode.json` remote MCP entry | `{env:INTEROPMCP_BASIC}` | Per-user; never committed. |
| `INTEROPMCP_MODE` | environment | `secured` | Drives setup and the startup validator. |
| `INTEROPMCP_DEMO_PASSWORD` | environment | secret | Used by the demo bootstrap; never committed. |
| `INTEROPMCP_BASIC` | environment | `Basic <base64(user:password)>` | Client-side only; never logged. Must be exported by the process that launches OpenCode (persist in `~/.bashrc`), not only present in `.env`. |

## Relationships

```text
IRIS user ──N:M──▶ Access role (InteropMCPRoles) ──N:M──▶ Gateway entitlement (InteropMCP_Access)
                                                              │
                                                              ▼
                                              Endpoint protection (Type 18 app)
                                                              │
                                                              ▼
                                              MCPService (Parameter RESOURCE)
                                                              │
                              ┌───────────────────────────────┴───────────────────────────────┐
                              ▼                                                               ▼
                    Tool invocation (Invocations)                         Access decision (%SYS.Audit)
                    AgentIdentity = $USERNAME                             AccessDenied / AuthenticationDenied
```

## Validation rules summary

- Mode is one of `secured`/`demo`; unknown values fail setup.
- `InteropMCP_Access` exists exactly once; public permission is empty.
- `InteropMCPRoles` includes `InteropMCP_Access:U`; no broad administrative role.
- Secured app: `AutheEnabled=32`, `Resource=""`, `MatchRoles=""`, `LoginPage=""`.
- Demo app: `AutheEnabled=64`, `Resource=""`, `MatchRoles=":%All"`, `LoginPage=""`.
- `MCPService` `RESOURCE` is non-empty in secured mode.
- `AuditEnabled=true` in secured mode.
- Every invocation has a non-empty `AgentIdentity`; never `"agent"`.
- Every denial has an audit row with outcome, time, and username claim; no credential.
- Re-running setup in the same mode changes no access behavior and creates no duplicate
  definitions.
- The startup validator rejects `allow_anonymous`/mode mismatches and endpoint credentials in
  secured mode.
