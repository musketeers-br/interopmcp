# Contract: Admin API (ObjectScript class methods)

**Feature**: specs/001-interop-mcp | **Date**: 2026-10-19

Operator/administration surface for catalog management, approvals, and health. Class-method
contract in namespace `IRISAPP` (v1; a REST wrapper may be added later without breaking this
contract). All methods return `%Status` unless noted and log at appropriate levels.

## br.musketeers.InteropMCP.Registry

| Method | Signature (conceptual) | Behavior |
|--------|------------------------|----------|
| BuildCatalog | `BuildCatalog(pProduction As %String) As %Status` | Scans annotated Business Services of the production, regenerates + compiles the gateway Tools class, refreshes ToolDefinition cache, publishes catalog (FR-001, FR-002, FR-014). Idempotent. |
| ListTools | `ListTools() As %List / %SQL query` | Returns current published catalog with classification and enabled state |
| SetEnabled | `SetEnabled(pTool As %String, pEnabled As %Boolean) As %Status` | Enables/disables a tool; disabled tools leave the catalog (FR-013) |
| GetConfig | `GetConfig() As %DynamicObject` | Wait window, auth mode, log level (GatewaySettings) |

Build failure modes: duplicate tool name → error naming both services (FR-014); no annotated
services → error (empty catalog is never published silently).

## br.musketeers.InteropMCP.Approvals

| Method | Signature (conceptual) | Behavior |
|--------|------------------------|----------|
| ListPending | `ListPending() As %ResultSet` | All `pending` requests with invocation context |
| Approve | `Approve(pApprovalId As %String, pApprover As %String) As %Status` | Sets decision `approved`; releases invocation to `executing` (FR-009) |
| Reject | `Reject(pApprovalId As %String, pApprover As %String, pReason As %String) As %Status` | Sets decision `rejected`; invocation becomes `rejected`, never executes; caller agent sees failed status |
| Cancel | `Cancel(pApprovalId As %String, pOperator As %String) As %Status` | Operator cancellation of stale pending items (Edge Case; alias of Reject with reason `cancelled`) |

Every decision is recorded in the invocation store and the platform audit log (FR-018).

## br.musketeers.InteropMCP.Health

| Method | Signature (conceptual) | Behavior |
|--------|------------------------|----------|
| GetStatus | `GetStatus() As %DynamicObject` | `{ production: running/stopped, productionName, catalogSize, pendingApprovals, lastInvocationAt, logLevel }` for monitoring systems (FR-017) |

## br.musketeers.InteropMCP.Setup

| Method | Signature (conceptual) | Behavior |
|--------|------------------------|----------|
| Run | `Run(pMode As %String = "dev") As %Status` | Idempotent provisioning: web application (Type 18, dispatch `br.musketeers.InteropMCP.MCPService`), auth mode per `pMode` (`dev` → unauthenticated local, otherwise platform auth + least-privilege role), demo production start, catalog build (R7) |

## br.musketeers.InteropMCP.MCPService

| Member | Behavior |
|--------|----------|
| `Parameter SPECIFICATION = "br.musketeers.InteropMCP.ToolSet"` | Binds the MCP service to the gateway ToolSet (sample pattern) |

## br.musketeers.InteropMCP.Log (internal, exercised indirectly)

| Method | Signature (conceptual) | Behavior |
|--------|------------------------|----------|
| Write | `Write(pLevel As %String, pComponent As %String, pMessage As %String, pData As %DynamicObject = "")` | Levels `debug|info|warn|error`; component tags (`registry`, `guardrail`, `invoker`, `approval`, `mcp`); respects configured level (FR-016) |

## Invariants

- Admin methods are never exposed as MCP tools; agents cannot approve their own critical
  calls (FR-009, spec out-of-scope).
- `BuildCatalog` is the only writer of ToolDefinition; invocation/approval stores are
  append-oriented (audit integrity, SC-002).
