# Feature Specification: Workflow Approval Integration

**Feature Branch**: `003-workflow-approval-bridge`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "@docs/spec-workflow-aprovaçoes.txt e depois gere uma nova branch para essa spec com um nome adequado"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operator Approves Critical Tool Call via Management Portal (Priority: P1)

An operator receives a pending approval for a critical tool call triggered by an AI agent, views the approval request in the IRIS Management Portal Workflow interface, reviews the details of the tool invocation (tool name, agent identity, parameters), and approves or rejects the request. Upon approval, the original invocation is executed with the same parameters and agent identity.

**Why this priority**: This is the primary use case for integrating native IRIS Workflow with the existing approval mechanism. Without it, operators are forced to use terminal commands to approve critical calls, limiting visibility and auditability.

**Independent Test**: Can be fully tested by creating a critical tool invocation, verifying the Workflow task is created, completing the task via the Management Portal, and confirming the invocation status changes to completed with proper audit trail.

**Acceptance Scenarios**:

1. **Given** a critical tool is invoked by an AI agent, **When** the invocation is held for approval, **Then** a Workflow task is created linked to the approval request and visible in the Management Portal
2. **Given** a Workflow task exists for a pending approval, **When** an operator approves the task via the portal, **Then** the approval is recorded, the invocation is replayed, and the status changes to completed
3. **Given** a Workflow task exists for a pending approval, **When** an operator rejects the task via the portal with a reason, **Then** the approval is recorded as rejected, the invocation is marked as rejected, and the Business Service is never executed

---

### User Story 2 - Concurrent Approval Race Condition Handling (Priority: P2)

Multiple operators attempt to decide the same pending approval simultaneously (one via terminal, one via Workflow portal). The system ensures only the first decision is honored, locking the approval record during decision processing and returning an explicit error to the losing operator.

**Why this priority**: Prevents conflicting decisions and ensures audit integrity when approvals are handled through multiple interfaces concurrently.

**Independent Test**: Can be tested by simulating concurrent approval attempts on the same ApprovalId and verifying only one succeeds while the other receives a clear "already decided" error.

**Acceptance Scenarios**:

1. **Given** an approval is pending, **When** two operators attempt to approve/reject simultaneously, **Then** only the first decision is persisted and the second attempt returns an error stating the approval was already decided by the first operator
2. **Given** an approval has been decided, **When** a subsequent attempt is made to approve/reject, **Then** the system returns an explicit error indicating the approval is no longer pending

---

### User Story 3 - Audit Trail Consistency Across Interfaces (Priority: P3)

Approval decisions made via terminal commands and via Workflow portal are recorded consistently in the same audit stores, allowing operators and auditors to review all decisions from a single source of truth regardless of the interface used.

**Why this priority**: Maintains audit coherence and prevents fragmentation of decision records across different interfaces.

**Independent Test**: Can be tested by making approvals through both interfaces and verifying all decisions appear in both `br.musketeers.InteropMCP.Approvals` and Workflow task history with consistent data.

**Acceptance Scenarios**:

1. **Given** an approval is decided via terminal, **When** the decision is queried via SQL or Workflow portal, **Then** the decision appears in both audit stores with matching approver, timestamp, and reason
2. **Given** an approval is decided via Workflow portal, **When** the decision is queried via terminal commands, **Then** the decision appears in both audit stores with matching data

---

### Edge Cases

- What happens when Workflow task creation fails after ApprovalRequest creation? The approval remains usable via terminal with a warning logged, maintaining backward compatibility.
- How does system handle approval requests without a corresponding Workflow task (legacy approvals created before integration)? Approvals without TaskId remain fully functional via terminal commands.
- What happens when an operator approves via Workflow but the invocation replay fails? The approval decision is persisted as approved, invocation status is updated to failed with error details, and audit records reflect the failure.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST maintain `br.musketeers.InteropMCP.Approvals` as the single source of truth for approval decisions
- **FR-002**: System MUST add `TaskId` property to `Approvals` class linking each approval to an `Ens.Workflow.Task`
- **FR-003**: System MUST create a Workflow task when a critical tool invocation is held for approval
- **FR-004**: System MUST allow operators to approve/reject approvals via both terminal commands and Workflow Management Portal
- **FR-005**: System MUST enforce exclusive locking during approval decision to prevent race conditions
- **FR-006**: System MUST return explicit error when attempting to decide an already decided approval
- **FR-007**: System MUST replay the original tool invocation with original parameters and agent identity when approval is granted
- **FR-008**: System MUST mark invocation as rejected with reason when approval is rejected
- **FR-009**: System MUST synchronize approval state between `Approvals` table and Workflow task status
- **FR-010**: System MUST log all approval decisions with approver identity, timestamp, and reason

### Key Entities

- **Approvals**: Represents a human approval request for a critical tool invocation. Key attributes: ApprovalId (GUID), InvocationId, TaskId (link to Workflow), Decision (pending/approved/rejected), Approver, DecidedAt, Reason
- **Invocations**: Represents a tool call audit record. Key attributes: InvocationId, ToolName, AgentIdentity, Parameters, Status (received/pending-approval/executing/completed/rejected), Result, ErrorMessage
- **Workflow Task**: Native IRIS Workflow task representing the approval request for operator action. Linked to Approval via TaskId

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can review pending approvals in Management Portal Workflow interface within 2 minutes of invocation hold
- **SC-002**: 100% of approval decisions made via Workflow portal are correctly reflected in `Approvals` table with matching audit data
- **SC-003**: Concurrent approval attempts on same ApprovalId result in clear error for losing attempt with 100% consistency
- **SC-004**: Critical tool invocations approved via Workflow complete successfully with original parameters preserved in 100% of cases
- **SC-005**: Audit trail shows complete lineage from tool invocation through approval decision to execution result

## Assumptions

- IRIS Interoperability Workflow module is available and configured in the target environment
- Existing `Approvals` approval mechanism remains fully functional when Workflow is unavailable
- Operators authenticate via session-based IRIS user accounts with appropriate security roles for Workflow portal access
- Workflow task forms can be customized to display tool invocation details
- No automatic expiration of pending approvals is required for initial implementation
- Approval decisions are made by human operators with valid user identities

## Clarifications

### Session 2026-11-01

- Q: Como deve ser a autenticação dos operadores para acesso ao portal de Workflow? → A: Autenticação baseada em sessão com contas de usuário IRIS existentes (Opção A)
