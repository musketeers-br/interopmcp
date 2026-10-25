# API Reference — IRIS InteropMCP

Two surfaces: the **MCP protocol contract** consumed by agents, and the **ObjectScript
admin API** consumed by operators.

> All `br.musketeers.InteropMCP` classes carry in-code documentation (English `///` docstrings on
> classes, methods, properties and parameters), viewable in the InterSystems class
> reference (Management Portal → View Class Documentation) and in IDE tooltips. This page
> is the operational summary; the class reference is the authoritative detail.

## 1. MCP protocol (agent-facing)

Transport: MCP streamable HTTP at `http://localhost:8080/mcp/interopmcp` (through
`iris-mcp-server`). Full JSON shapes: [`contracts/mcp-protocol.md`](../../specs/001-interop-mcp/contracts/mcp-protocol.md).

### Methods

| Method | Behavior |
|--------|----------|
| `initialize` / `notifications/initialized` | Standard MCP lifecycle; the bridge issues an `mcp-session-id` |
| `tools/list` | All published tools with descriptions and generated input schemas |
| `tools/call` | Executes a tool; guardrails apply per classification |

### Tools (from the demo production)

| Tool | Arguments | Pathway |
|------|-----------|---------|
| `PayLookup` | `OrderId` (string, required), `CustomerId` (string) | readonly — executes immediately |
| `CustomerUpdate` | `CustomerId` (string, required), `NewAddress` (string, required) | write — requires authorization; executes when authorized |
| `RiskCheck` | `Cnpj` (string, required), `Scope` (string) | critical — queued for human approval, never auto-executed |
| `BatchRun` | `ReportSet` (string, required) | readonly, async-flagged — returns processing reference |
| `GetInvocationStatus` | `invocationId` (string, required) | returns invocation rows (status/result) |

Note: the bridge prefixes tool names with the endpoint service (`mcp_interopmcp_PayLookup`).

### Error contract

| Condition | Result |
|-----------|--------|
| Unknown tool | MCP error response |
| Schema violation | MCP error listing failing parameters |
| Backing service disabled/stopped | Tool hidden from `tools/list`; call returns `service_unavailable` |
| Unauthenticated remote caller | Transport-level rejection (dev endpoints only allow anonymous on localhost) |
| Duplicate tool names | Catalog build fails; nothing ambiguous is published |

## 2. ObjectScript admin API

Namespace `IRISAPP`. All methods return `%Status` unless noted.

### br.musketeers.InteropMCP.Registry

| Method | Signature | Purpose |
|--------|-----------|---------|
| `BuildCatalog` | `BuildCatalog(pProduction As %String) As %Status` | Scans annotated Business Services, regenerates + compiles `br.musketeers.InteropMCP.GeneratedTools`, publishes catalog. Idempotent. Fails on duplicate tool names (naming both services) |
| `ListTools` | `ListTools(Output pTools As %DynamicObject) As %Status` | Current catalog (name, classification, description, async, wait, enabled) |
| `SetEnabled` | `SetEnabled(pTool As %String, pEnabled As %Boolean) As %Status` | Toggle a tool in the published catalog |
| `GetToolDefinition` | `GetToolDefinition(pTool As %String, Output pDef As %DynamicObject) As %Status` | One tool definition (used by Guardrails/Invoker) |
| `GetConfig` | `GetConfig() As %DynamicObject` | `waitWindowSeconds` (default 30) |

```objectscript
zn "IRISAPP"
Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
Set tools = ""
Do ##class(br.musketeers.InteropMCP.Registry).ListTools(.tools)
Write tools.%ToJSON()
```

### br.musketeers.InteropMCP.Guardrails

| Method | Signature | Purpose |
|--------|-----------|---------|
| `Check` | `Check(pTool, pParams, pAgent, Output pProceed, Output pHoldId, Output pSC)` | Classification choke point. `readonly` → proceed; `write` → validation + authorization; `critical` → creates approval request, `pProceed = 0`, `pHoldId = <approvalId>` |

Generated tool methods call `Check` **before** `Invoker` — the enforcement cannot be
bypassed by catalog regeneration.

### br.musketeers.InteropMCP.Approvals

| Method | Signature | Purpose |
|--------|-----------|---------|
| `CreateRequest` | `CreateRequest(pInvocationId, Output pApprovalId) As %Status` | (internal) creates a `pending` request |
| `ListPending` | `ListPending(Output pList As %DynamicObject) As %Status` | All pending approval ids |
| `Approve` | `Approve(pApprovalId, pApprover) As %Status` | Approves; releases the invocation |
| `Reject` | `Reject(pApprovalId, pApprover, pReason) As %Status` | Rejects; the invocation never executes |
| `Cancel` | `Cancel(pApprovalId, pOperator, pReason) As %Status` | Operator cancellation (alias of `Reject`) |

### br.musketeers.InteropMCP.Invocations

| Method | Signature | Purpose |
|--------|-----------|---------|
| `CreateInvocation` | `CreateInvocation(pTool, pAgent, pParams, Output pId) As %Status` | (internal) records `received` |
| `UpdateStatus` | `UpdateStatus(pId, pStatus, pResult, pError, pHeaderId) As %Status` | (internal) lifecycle transitions |

Statuses: `received → executing → completed | failed`, and
`received → pending-approval → executing | rejected` (critical path — `rejected` never
executes). Row model: `InvocationId` (GUID), `ToolName`, `AgentIdentity`, `Parameters`
(JSON), `Status`, `Result` (JSON), `ErrorMessage`, `MessageHeaderId` (reserved),
`StartedAt`, `EndedAt`.

### br.musketeers.InteropMCP.Health

| Method | Signature | Purpose |
|--------|-----------|---------|
| `GetStatus` | `GetStatus() As %DynamicObject` | `{production, productionName, catalogSize, pendingApprovals, lastInvocationAt, logLevel}` |

### br.musketeers.InteropMCP.Setup

| Method | Signature | Purpose |
|--------|-----------|---------|
| `Run` | `Run(pMode As %String = "dev") As %Status` | Provisions the `/mcp/interopmcp` web app (Type 18). `dev` → unauthenticated + demo production start + catalog build; otherwise platform auth + `:InteropMCPRoles`. Idempotent |
| `TearDown` | `TearDown() As %Status` | Removes the web app |

### br.musketeers.InteropMCP.Log

| Method | Signature | Purpose |
|--------|-----------|---------|
| `Write` | `Write(pLevel, pComponent, pMessage, pData) As %Status` | Levels `debug\|info\|warn\|error`; components `registry\|guardrail\|invoker\|approval\|mcp`; persists to `^InteropMCP.LogD` + console. `MinLevel` parameter gates verbosity |

### Generated / status classes

| Class | Kind | Notes |
|-------|------|-------|
| `br.musketeers.InteropMCP.GeneratedTools` | `%AI.Tool` (generated) | Recreated by `Registry.GenerateToolsClass()` on every `BuildCatalog`; do not edit by hand. Ships as a stub so the module compiles before first build |
| `br.musketeers.InteropMCP.InvocationStatusTools` | `%AI.Tool` (static) | `GetInvocationStatus` query over `br.musketeers.InteropMCP.Invocations` |
| `br.musketeers.InteropMCP.ToolSet` | `%AI.ToolSet` | XData includes the two classes above |
| `br.musketeers.InteropMCP.MCPService` | `%AI.MCP.Service` | `SPECIFICATION = "br.musketeers.InteropMCP.ToolSet"`; dispatched by the `/mcp/interopmcp` web app |
