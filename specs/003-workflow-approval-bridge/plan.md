# Implementation Plan: Workflow Approval Integration

**Branch**: `003-workflow-approval-bridge` | **Date**: 2026-11-01 | **Spec**: `specs/003-workflow-approval-bridge/spec.md`

**Input**: Feature specification from `/specs/003-workflow-approval-bridge/spec.md`

## Summary

Integrate native IRIS Interoperability Workflow as the UI/assignment layer for the existing custom human-in-the-loop approval mechanism in InteropMCP. The `br.musketeers.InteropMCP.Approvals` class remains the single source of truth for approval decisions; `Ens.Workflow.Task` is only used to surface pending approvals to operators via the Management Portal. A new `WorkflowBridge` class connects the two, handling task creation, completion, and synchronization with the approval record.

## Technical Context

**Language/Version**: ObjectScript (InterSystems IRIS)

**Primary Dependencies**: `Ens.Workflow.Task`, `br.musketeers.InteropMCP.Approvals`, `br.musketeers.InteropMCP.Guardrails`, `br.musketeers.InteropMCP.Invoker`, `br.musketeers.InteropMCP.Invocations`, `br.musketeers.InteropMCP.Log`

**Storage**: IRIS globals (`^InteropMCP.ApprovalsD`), `%Persistent` classes with storage

**Testing**: IRIS `%UnitTest`

**Target Platform**: IRIS Interoperability namespace

**Project Type**: integration module for IRIS Interoperability

**Performance Goals**: N/A (human-in-the-loop, operator-driven decisions; sub-second response for task creation/completion)

**Constraints**: `Approvals` must remain the single source of truth (FR-001); exclusive lock during decision to prevent race conditions (FR-005); backward compatible — approvals without `TaskId` still functional via terminal; no automatic expiration of pending approvals

**Scale/Scope**: Operator-driven workflow; no high-volume automation; tasks created per critical tool invocation

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Constitution Principle | Status | Evidence |
|---|---|---|
| Container-Oriented Architecture | PASS | IRIS Interoperability is container-deployable; no new infrastructure required |
| Comprehensive Logging | PASS | All approval decisions logged via `br.musketeers.InteropMCP.Log` (component `approval`) with approver, timestamp, reason |
| Monitoring and Observability | PASS | Invocation status queryable via `GetInvocationStatus` and SQL over `Invocations`/`Approvals` tables |
| Security by Design | PASS | Session-based IRIS user accounts with security roles (clarified in spec Session 2026-11-01); least-privilege access to Workflow tasks |
| Technology Stack | PASS | ObjectScript for IRIS core business logic; no new languages or frameworks introduced |

All gates pass. No violations → Complexity Tracking section not required.

## Project Structure

### Documentation (this feature)

```text
specs/003-workflow-approval-bridge/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (empty — internal IRIS module, no external contracts)
└── tasks.md             # Phase 2 output (created by /speckit.tasks — NOT by this command)
```

### Source Code (repository root)

The project follows a single-package ObjectScript structure under `src/br/musketeers/InteropMCP/` (existing layout).

```text
src/br/musketeers/InteropMCP/
├── Approvals.cls              # Modified: add TaskId property + TaskIdIdx index
├── WorkflowBridge.cls         # New: CreateTask, ListPendingTasks, CompleteTask operations
├── Guardrails.cls             # Modified: call WorkflowBridge.CreateTask on critical hold path
├── Invoker.cls                # Unchanged (replay logic already exists)
├── Invocations.cls            # Unchanged (audit store already exists)
├── Log.cls                    # Unchanged (logging already exists)
└── Demo/
    └── RiskCheckBS.cls        # Unchanged (demo critical tool example)
```

**Structure Decision**: Single ObjectScript package under `src/br/musketeers/InteropMCP/`. No new directories, no frontend changes (Workflow UI is native IRIS Management Portal). Contracts directory is empty — this is an internal IRIS module with no external API contracts to expose.

## Phase 0: Outline & Research

No NEEDS CLARIFICATION markers remain in the spec (all resolved in Session 2026-11-01). Research tasks:

- Research IRIS `Ens.Workflow.Task` API for task creation/completion methods and required properties
- Research ObjectScript locking patterns (`$$$LOCK`/`$$$UNLOCK` or `%Open` with concurrency) for race condition prevention
- Research IRIS Management Portal Workflow task form customization for displaying invocation details

**Output**: `research.md` with all findings consolidated (Decision, Rationale, Alternatives considered per item)

## Phase 1: Design & Contracts

### data-model.md

Entities extracted from feature spec:

**Approvals** (modified, `%Persistent`)
- `ApprovalId` (%String, GUID) — unique identifier
- `InvocationId` (%String) — links to Invocations record
- `TaskId` (%String, MAXLEN=64, indexed unique) — links to `Ens.Workflow.Task`
- `Decision` (%String) — "pending" | "approved" | "rejected"
- `Approver` (%String) — operator username
- `DecidedAt` (%TimeStamp) — decision timestamp
- `Reason` (%String) — decision reason/comment
- Index: `TaskIdIdx On TaskId [ Unique ]`

**Invocations** (existing, unchanged)
- `InvocationId`, `ToolName`, `AgentIdentity`, `Parameters`, `Status`, `Result`, `ErrorMessage`

**Workflow Task** (native IRIS `Ens.Workflow.Task`, unchanged)
- Linked to Approval via `TaskId` stored in Approvals row

State transitions: pending → approved (replay invocation) | pending → rejected (mark invocation rejected)

### contracts/

Empty. This is an internal IRIS Interoperability module; no external contracts exposed. The Workflow portal UI is provided natively by IRIS Management Portal.

### quickstart.md

**Prerequisites**: IRIS Interoperability namespace with Workflow module configured; InteropMCP classes compiled

**Setup**:
1. Compile `WorkflowBridge.cls` and modified `Approvals.cls`/`Guardrails.cls`
2. Provision operator user with Workflow security roles in IRIS
3. Ensure `br.musketeers.InteropMCP.Approvals` data exists

**Test/run commands**:
1. Invoke a critical tool (e.g., `RiskCheck`) via MCP client → verify status `held` with `approvalId`
2. Verify Workflow task created and visible in Management Portal
3. Complete task via portal (approve) → verify invocation status changes to `completed`
4. Verify audit record in `Approvals` table with approver, timestamp, reason
5. Test concurrent approval: two simultaneous decisions on same `ApprovalId` → one succeeds, other returns explicit error

**Expected outcomes**: SC-001 through SC-005 all measurable and verifiable

**Re-evaluate Constitution Check post-design**: All gates still pass — no new languages, logging preserved, security by design maintained, container-compatible.

---

**Done When**: Phase 1 artifacts generated (`research.md`, `data-model.md`, `quickstart.md`, `contracts/` empty), Constitution Check passes both before Phase 0 and after Phase 1.

**Next command**: `/speckit.tasks` to generate implementation task list.