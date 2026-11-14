# InteropMCP security and authentication: who can call your MCP tools

## 1. Authentication model

InteropMCP is published as an IRIS web application of type 18 (served by the IRIS private web server, not the Apache CSP Gateway):

| Property | Value |
|----------|-------|
| Path | `/mcp/interopmcp` |
| Dispatch class | `br.musketeers.InteropMCP.MCPService` (`%AI.MCP.Service`) |
| Type | 18 |
| Authentication | `AutheEnabled = 32` (platform / password) |
| Target namespace | `IRISAPP` |
| MatchRoles | (empty) |

The endpoint is provisioned idempotently by `br.musketeers.InteropMCP.Setup.ProvisionApplication()`. With `AutheEnabled = 32`, any HTTP request without a valid credential is rejected with `401 Unauthorized` before reaching the MCP service. The `iris-mcp-server` bridge (port 8080) forwards the caller's `Authorization` header to IRIS through the superserver (port 1972).

### Validate with Opencode

**With valid credentials**

```bash
export INTEROPMCP_BASIC="Basic $(printf 'mcp_demo:change-me' | base64 -w0)"
opencode
```

The MCP Servers panel shows `InteropMCP ✓ connected`. Listing tools returns the correct list:

`List the available InteropMCP tools in table with tool name and thier parameters`

![Opencode connected with valid auth](img/article-2-step-02-opencode-auth.png)

**Without credentials / invalid token**

```bash
unset INTEROPMCP_BASIC
# or use a wrong user, e.g.
# export INTEROPMCP_BASIC="Basic $(printf 'bad:user' | base64 -w0)"
opencode
```

The panel still shows `InteropMCP ✓ connected`. Authentication problems are not surfaced directly in the server panel. The only indirect evidence is when listing tools: the agent hallucinates an incorrect tool list instead of reporting a clear 401 error.

![Opencode connected without valid auth – tool list is hallucinated](img/article-2-step-02-opencode-no-auth.png)

### Validate with Raw HTTP validation

#### 401 without credentials
```bash
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
# Expected: 401
```

#### 200 with valid Basic auth
```bash
export INTEROPMCP_BASIC="Basic $(printf 'mcp_demo:change-me' | base64 -w0)"
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: $INTEROPMCP_BASIC" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo": {"name":"conformance","version":"1"}}}' 
# Expected: 200
```

## 2. Resource, role, and least-privilege grants

The setup creates (or reconciles) security objects in `%SYS`:

| Object | Name | Purpose |
|--------|------|---------|
| Resource | `InteropMCP_Access` | Gates access to the MCP endpoint |
| Role | `InteropMCPRoles` | Least-privilege role for MCP callers |

The role carries these minimum grants (`RoleResources`):

```
InteropMCP_Access:U,
%DB_IRISAPP_CODE:R,
%DB_IRISAPP_DATA:RW,
%DB_IRISLIB:R,
%DB_IRISTEMP:RW,
%Service_SQL:U
```

- `U` = use (connect), `R` = read, `RW` = read/write.
- The role also receives `GRANT SELECT` on the gateway's own tables (`Invocations`, `Approvals`) via `EnsureSqlPrivileges()`, because database-level grants alone do not confer SQL table privileges.

### Demo users

The container bootstrap (`br.musketeers.InteropMCP.Demo.Setup.EnsureDemoUsers`) creates two users from `INTEROPMCP_DEMO_PASSWORD` (default `change-me`):

| User | Role | Can call MCP tools? |
|------|------|---------------------|
| `mcp_demo` | `InteropMCPRoles` | Yes (entitled) |
| `mcp_demo2` | (none) | No — `403` |

### Validate with Opencode

Switch `INTEROPMCP_BASIC` to user `mcp_demo2` which has no role:
```bash
export INTEROPMCP_BASIC="Basic $(printf 'mcp_demo2:change-me' | base64 -w0)"
opencode
```

Opencode still reports `InteropMCP ✓ connected`. Role enforcement is not shown directly in the server panel. Evidence is indirect: asking to list tools results in hallucination / an empty/incorrect list, and tool calls cannot be executed. With `mcp_demo2` no tool can be used, confirming role enforcement.

![Opencode 403 – user without InteropMCPRoles](img/article-2-step-03-opencode-user-no-priv.png)

### Validate with Raw HTTP validation

Role enforcement can be observed via `tools/list`. With a user without `InteropMCPRoles` the list is empty; with an entitled user the tools array is returned. This matches the Opencode behavior described above.

```bash
export INTEROPMCP_BASIC2="Basic $(printf 'mcp_demo2:change-me' | base64 -w0)"
export HEADER_FILE=$(mktemp)

# Enviando initialize (com o redirecionamento corrigido na mesma linha)
curl -s -D "$HEADER_FILE" -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: $INTEROPMCP_BASIC2" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"shell-client","version":"1"}}}' > /dev/null

# Extrai o mcp-session-id dos headers salvos (case-insensitive)
export SESSION_ID=$(grep -i "mcp-session-id:" "$HEADER_FILE" | tr -d '\r' | awk '{print $2}' | tr -d '\r')
rm -f "$HEADER_FILE"

# Buscando tools/list
echo "--------------------------------------------------------------------------------"
export RESPONSE=$(curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: $INTEROPMCP_BASIC2" \
  -H "Mcp-Session-Id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')

echo "Tools:"
echo "$RESPONSE" | grep '^data: {' | sed 's/^data: //' | jq '.result.tools'
```

> With `mcp_demo2` the result is an empty list:
```bash
Tools: []
```

```bash
export INTEROPMCP_BASIC2="Basic $(printf 'mcp_demo:change-me' | base64 -w0)"
export HEADER_FILE=$(mktemp)

# Enviando initialize (com o redirecionamento corrigido na mesma linha)
curl -s -D "$HEADER_FILE" -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: $INTEROPMCP_BASIC2" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"shell-client","version":"1"}}}' > /dev/null

# Extrai o mcp-session-id dos headers salvos (case-insensitive)
export SESSION_ID=$(grep -i "mcp-session-id:" "$HEADER_FILE" | tr -d '\r' | awk '{print $2}' | tr -d '\r')
rm -f "$HEADER_FILE"

# Buscando tools/list
echo "--------------------------------------------------------------------------------"
export RESPONSE=$(curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: $INTEROPMCP_BASIC2" \
  -H "Mcp-Session-Id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')

echo "Tools:"
echo "$RESPONSE" | grep '^data: {' | sed 's/^data: //' | jq '.result.tools'
```

> With `mcp_demo` the result is a populated array:
```bash
Tools: [...]
```

## 4. Per-tool guardrails

Authentication opens the door; each tool's classification decides what happens next. The classification comes from the Business Service class parameter `AIGATEWAY` and is enforced by `br.musketeers.InteropMCP.Guardrails.Check` before any Business Service is fired:

| Classification | Behavior | Demo example |
|---------------|----------|--------------|
| `readonly` | Immediate execution, no extra authorization | `PayLookupBS` — check payment |
| `write` | Authorized caller, decision logged | `CustomerUpdateBS` — update address; `RiskCheckBS` — risk assessment |
| `critical` | No execution: creates `pending-approval` invocation + approval request; runs only after an operator decides via the IRIS User Portal Workflow inbox (**Accept** → **Approve**/**Reject**) or via terminal `Approvals.Approve`/`Reject` | `AccountBlockBS` — account inactivation |

### Validate with Opencode

`readonly` — executes immediately

`Use the PayLookup tool with OrderId 88201 and CustomerId C-1`

Expected: `isError:false`, content type text with a JSON object:
```json
{
  "_status": "ok",
  "invocationId": "<INVOCATION_ID>",
  "message": "Tool executed successfully."
}
```

`write` — executes for authorized caller

`Use the CustomerUpdate tool with CustomerId 1 and NewAddress "Av. Paulista, 1000"`

Expected: `isError:false`, content type text with a JSON object (same structure as above).

`critical` — held for approval, Business Service never runs on the agent's call

`Use the AccountBlock tool with CustomerId 1, BlockType "permanent", and Reason "Restricted CNPJ detected"`

Expected: `isError:false`, content type text with a JSON object:
```json
{
  "_status": "held",
  "invocationId": "<INVOCATION_ID>",
  "approvalId": "<APPROVAL_ID>",
  "message": "Critical call held for approval. Use GetInvocationStatus with invocationId to check progress."
}
```

![Guardrails via Opencode – readonly/write execute, critical held for approval](img/article-2-step-04-opencode-guardrails.png)

## 5. Human-in-the-loop approval for critical tools

Critical calls are parked in `pending-approval`. The operator decides in the **IRIS User Portal Workflow inbox** — this is the primary UI:

1. Open the DeepSee User Portal Workflow:
   ```
   http://localhost:52773/csp/irisapp/_DeepSee.UserPortal.Workflow.zen
   ```
2. Login as a user with the `Operators` role (e.g. `_SYSTEM`/`SYS`).
3. In the inbox, select the task with Subject `Approval: <ApprovalId>` (status `Unassigned`).
4. Click **Accept** to take ownership — the portal then shows **Relinquish** / **Approve** / **Reject**.
5. Click **Approve** or **Reject** and confirm.

The portal dispatches `EnsLib.Workflow.Engine.%ProcessAction` → `TaskResponse.OnAction` on the stored task class. InteropMCP provides `br.musketeers.InteropMCP.WorkflowTaskResponse`, whose `OnAction` records the decision in `Approvals` and **closes the task locally — no deferred response is needed** because the approval request was created outside a production message flow. This avoids `Ens.ErrProductionMismatchInDeferredResponse` (see `docs/ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE.md` and `docs/ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE_ANALYSIS.md`).

**Terminal fallback (headless operator).** If the operator works only through the terminal, the same decision can be recorded without the portal — this path also bypasses `Ens.Host.SendDeferredResponse` entirely:

```bash
docker exec -it ai-hub-dev-template-iris-1 iris session iris -U IRISAPP
```

```objectscript
// List pending approvals
Set pend = ""
Do ##class(br.musketeers.InteropMCP.Approvals).ListPending(.pend)
Write pend.%ToJSON(), !   // {"pending":["<ApprovalId>", ...]}

// Get the approval ID
Set ApprovalId = pend.pending.%Get(1)

// Approve
Do ##class(br.musketeers.InteropMCP.Approvals).Approve(ApprovalId, "operator1")

// Reject (requires a reason)
Do ##class(br.musketeers.InteropMCP.Approvals).Reject(ApprovalId, "operator1", "policy violation")
```

There is no automatic expiry: pending items remain until decided or explicitly cancelled. Every decision is written to `br_musketeers_InteropMCP.Approvals` and to the gateway log (`br.musketeers.InteropMCP.Log`, component `approval`).

### Validate: query pending approvals via SQL

```sql
SELECT ApprovalId, InvocationId, Decision, Approver, DecidedAt, Reason
FROM br_musketeers_InteropMCP.Approvals
```

Example row from a validated call:

| ApprovalId | InvocationId | Decision | Approver | DecidedAt | Reason |
| :--- | :--- | :--- | :--- | :--- | :--- |
| BFC822EB-D56D-11F1-A5D9-9E34AEE9AC56 | BFC7AFB8-D56D-11F1-A5D9-9E34AEE9AC56 | approved | operator1 | 2026-10-31 21:09:45 | |
| 1065D800-D601-11F1-A5D9-9E34AEE9AC56 | 1065AF61-D601-11F1-A5D9-9E34AEE9AC56 | pending | | | |
| 517C7120-D618-11F1-A5D9-9E34AEE9AC56 | 517C41E3-D618-11F1-A5D9-9E34AEE9AC56 | approved | operator1 | 2026-11-01 17:26:08 | |


### Validate: query pending approvals via Opencode

`Check the status of account block "<InvocationId>"`

![Gateway invocations and approvals (SQL audit)](img/article-2-step-06-approval-opencode.png)

## 6. Two separate audit planes

By design, the gateway and the production keep independent audit trails:

| Plane | Storage | Written by | Purpose |
|-------|---------|------------|---------|
| Production-native | `Ens.MessageHeader`, message store, Visual Trace, `^InteropMCP.Demo.AuditD` | The production components (BS → BP → BO) | Corporate audit of what the integration executed |
| Gateway | `br_musketeers_InteropMCP.Invocations`, `Approvals`, `^InteropMCP.LogD` | The gateway code | Tool-call lifecycle: agent identity, parameters, guardrail decisions, approvals |

The gateway never writes into production structures — it only fires Business Services via `CreateBusinessService` + `ProcessInput`.

### Validate: view gateway invocations

```sql
SELECT InvocationId, ToolName, AgentIdentity, Status, StartedAt, EndedAt
FROM br_musketeers_InteropMCP.Invocations ORDER BY StartedAt DESC
```

Example row from a rejected call:

| InvocationId | ToolName | AgentIdentity | Status |
|--------------|----------|---------------|--------|
| `1A199A17-…` | `AccountBlock` | `mcp_demo` | `rejected` |

Example row from a validated call:

| InvocationId | ToolName | AgentIdentity | Status |
|--------------|----------|---------------|--------|
| `B7805121-…` | `CustomerUpdate` | `mcp_demo` | `completed` |

And a pending critical approval:

| ApprovalId | InvocationId | Decision | Approver |
|------------|--------------|----------|----------|
| `62ADC228-…` | `62AD9123-…` | `pending` | (none) |

---

InteropMCP's security is layered: endpoint authentication, least-privilege role, per-tool guardrails, and dual-plane audit — so you can expose existing IRIS integrations to AI agents without surrendering control over who executes what.

---
*This article was drafted with AI assistance and reviewed by the author.*

**Repository:** `src/br/musketeers.InteropMCP/Setup.cls`, `Guardrails.cls`, `Invoker.cls`, `Approvals.cls`, `Log.cls` and `docs/interop-mcp/architecture.md`.
