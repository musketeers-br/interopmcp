# Contract: Admin API (ObjectScript class methods)

**Feature**: `002-mcp-gateway-auth` | **Date**: 2026-10-25

Operator/provisioning surface for authentication, authorization, and audit. All methods run
in the gateway namespace unless stated otherwise. Methods return `%Status` unless noted.

## br.musketeers.InteropMCP.Setup

### `Run(pMode As %String = "prod") As %Status`

Idempotent, mode-aware provisioning of the `/mcp/interopmcp` endpoint.

| Mode input | Normalized mode | Effect |
|------------|-----------------|--------|
| `"prod"`, `"secured"` | `secured` | Password auth, service-level entitlement, no role grants. |
| `"dev"`, `"demo"` | `demo` | Unauthenticated, `:%All` role grant, local-dev identity. |
| anything else | — | Error naming the accepted values; no changes. |

Steps:

1. Validate the mode; reject unknown values.
2. Call `EnsureSecurity()`.
3. In secured mode, assert
   `$PARAMETER("br.musketeers.InteropMCP.MCPService","RESOURCE")` is non-empty; fail with an
   actionable error if not.
4. Create or reconcile the Type 18 application:
   - secured: `AutheEnabled=32`, `Resource=""`, `MatchRoles=""`, `LoginPage=""`;
   - demo: `AutheEnabled=64`, `Resource=""`, `MatchRoles=":%All"`, `LoginPage=""`.
   - `Type=18`, `NameSpace=target`, `DispatchClass=br.musketeers.InteropMCP.MCPService`,
     `Enabled=1`.
5. Only after successful app provisioning, write `^InteropMCP.Config("mode")` = `secured` or
   `demo`.
6. Return `%Status`; on failure, leave the previously provisioned state intact where possible.

**Idempotency**: `Security.Applications.Exists()` → `Modify()`; otherwise `Create()`.
Re-running in the same mode must not duplicate the app, resource, or role and must not change
access behavior.

**Out of scope**: starting productions, building catalogs, creating demo users, or reading the
bridge's TOML configuration. Those belong to the demo bootstrap and the startup validator.

### `EnsureSecurity() As %Status`

Creates or reconciles the security objects required by both modes.

| Object | Rule |
|--------|------|
| Resource `InteropMCP_Access` | `Security.Resources.Exists()`; if absent, `Create(Name, Description, "", 9)`. If present, leave it unchanged. |
| Role `InteropMCPRoles` | `Security.Roles.Get()`; if absent, `Create("InteropMCPRoles", Description, "InteropMCP_Access:U,...", "", 0)`. If present, read `Resources`, add any missing required grants, preserve unrelated grants, and `Modify()`. |
| Audit system | In secured mode, read `Security.System` and require `AuditEnabled=1`; otherwise fail with an error naming the setting. |

**Required role grants**: `InteropMCP_Access:U`, plus the minimum database/service grants
documented in [data-model.md](../data-model.md). The exact database resource names are
environment-specific; production replaces the demo grants with its own minimum.

### `TearDown() As %Status`

Deletes the `/mcp/interopmcp` application. Does **not** delete `InteropMCP_Access` or
`InteropMCPRoles`: other users/applications may depend on them, and deletion would silently
revoke access. Idempotent.

## br.musketeers.InteropMCP.MCPService

### `Parameter RESOURCE = "InteropMCP_Access"`

The framework checks this resource on every REST and WebSocket request through
`%IsAuthorized`. The parameter is mandatory in secured mode; `Setup.Run` asserts it.

### `AccessCheck(Output pAuthorized As %Boolean = 0) As %Status`

Override of `%AI.MCP.Service.AccessCheck`:

```text
Set sc = ##super(.pAuthorized)
If 'pAuthorized Do ..RecordAccessDecision("entitlement-denied", "missing InteropMCP_Access")
Quit sc
```

- `##super` must be used (not `##class(%AI.MCP.Service).AccessCheck`) so the subclass
  `RESOURCE` parameter is evaluated.
- The base method sets the 403 response; the override must not replace it.
- The audit write must not change the returned status or turn the denial into a 500.
- Runs on every REST tool request, including requests in an already-open HTTP session.

### `Login(skipheader As %Boolean = 1) As %Status`

Override of the authentication-failure handler:

```text
Do ..RecordAccessDecision("authentication-denied", ..UsernameClaim())
Quit ##super(skipheader)
```

- `UsernameClaim()` parses the Basic `Authorization` header from `%request` and returns only
  the username part; the password and the encoded token are discarded.
- The base `Login()` returns the JSON 401; the override must preserve that response.
- Invalid passwords are also recorded by IRIS as `%LOGIN` / `LoginFailure`; duplicate records
  are acceptable and are documented.

### `RecordAccessDecision(pOutcome As %String, pReason As %String = "") As %Status` *(private)*

Writes one platform audit event:

```text
Set event = $Select(pOutcome = "entitlement-denied": "AccessDenied", 1: "AuthenticationDenied")
Set endpoint = $Get(%request.CgiEnvs("REQUEST_URI"))
Set data = "user="_$USERNAME_";endpoint="_endpoint_";outcome="_pOutcome
If pReason '= "" Set data = data_";reason="_pReason
Set ok = ##class(%SYS.Audit).WriteToAuditFile(
    "InteropMCP", "INTEROPMCP", event, data, "InteropMCP access decision", 1)
Quit $$$OK
```

- `pOutcome` is `entitlement-denied` or `authentication-denied`; the audit `Event` is
  `AccessDenied` or `AuthenticationDenied` respectively.
- `$USERNAME` is populated by the platform; for missing credentials it may be
  `UnknownUser`, and the claim is carried in `EventData`.
- Never include `Authorization`, the Basic token, or the password.
- Audit failures are swallowed after a best-effort `Log.Write`; the HTTP response is unchanged.

## br.musketeers.InteropMCP.Guardrails

### `CurrentAgent() As %String`

| Condition | Return |
|-----------|--------|
| `^InteropMCP.Config("mode")` = `demo` | `local-dev` |
| `$USERNAME` is empty | `local-dev` |
| `$USERNAME` = `UnknownUser` | `local-dev` |
| otherwise | `$USERNAME` |

The method is deterministic and does not read request parameters. It is called by the
generated tool methods for both `Guardrails.Check` and `Invoker.Invoke`.

## br.musketeers.InteropMCP.InvocationStatusTools

### `GetInvocationStatus(invocationId As %String)`

```sql
SELECT InvocationId, Status, Result, AgentIdentity
FROM br.musketeers.InteropMCP.Invocations
WHERE InvocationId = :invocationId
```

`ROWSPEC = "InvocationId:%String,Status:%String,Result:%String,AgentIdentity:%String"`.

The added column exposes the authenticated caller (or `local-dev`) through the status tool.
The invocation ID remains the bearer reference in this phase; no cross-user filtering is
added.

## br.musketeers.InteropMCP.Registry

### `GenerateToolsClass() As %Status`

The generated source must contain:

```objectscript
Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check(
    "<tool>", params, ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent(),
    .proceed, .holdId, .gsc)
...
Set sc = ##class(br.musketeers.InteropMCP.Invoker).Invoke(
    "<tool>", params, ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent(),
    .invId, .resp)
```

No generated tool may pass the literal `"agent"`. `GeneratedTools.cls` is regenerated by the
catalog build and is never hand-edited.

## Error contract

| Condition | Result |
|-----------|--------|
| Unknown setup mode | `%Status` error naming `prod`/`secured`/`dev`/`demo`; no changes. |
| `MCPService` `RESOURCE` empty in secured mode | `%Status` error naming the class parameter. |
| `AuditEnabled=0` in secured mode | `%Status` error naming `Security.System.AuditEnabled`. |
| Resource/role/app creation or modify failure | `%Status` with the platform error; no partial app update where avoidable. |
| Audit sink failure during a denial | Request still returns 401/403; best-effort gateway log entry. |
