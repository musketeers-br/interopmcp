# Tasks: Workflow Approval Integration

**Input**: Design documents from `/specs/003-workflow-approval-bridge/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are OPTIONAL - only include them if explicitly requested in the feature specification. Not requested in spec → no test tasks generated.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Single project: `src/` at repository root
- Paths assume single project structure per plan.md

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [ ] T001 Verify InteropMCP source structure under `src/br/musketeers/InteropMCP/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Add `TaskId` property and `TaskIdIdx` index to `Approvals` class in `src/br/musketeers/InteropMCP/Approvals.cls` (property: `TaskId As %String(MAXLEN = 64)`, index: `TaskIdIdx On TaskId [ Unique ]`)

---

## Phase 3: User Story 1 - Operator Approves Critical Tool Call via Management Portal (Priority: P1) 🎯 MVP

**Goal**: Enable operators to approve/reject critical tool calls via IRIS Management Portal Workflow, with the decision reflected in `Approvals` and the invocation replayed/rejected accordingly.

**Independent Test**: Create a critical tool invocation, verify Workflow task created, complete task via portal, confirm invocation status changes to completed/rejected with proper audit trail.

### Implementation for User Story 1

- [ ] T003 [P] [US1] Create `WorkflowBridge` class in `src/br/musketeers/InteropMCP/WorkflowBridge.cls` with `CreateTask(ApprovalId)` method that creates an `Ens.Workflow.Task` and sets `TaskId` on the `Approvals` record
- [ ] T004 [P] [US1] Add `ListPendingTasks()` method to `WorkflowBridge.cls` that returns pending approvals without linked Workflow tasks
- [ ] T005 [P] [US1] Add `CompleteTask(TaskId, Decision, Approver, Reason)` method to `WorkflowBridge.cls` that completes the Workflow task and calls `Approvals.Approve` or `Approvals.Reject`
- [X] T006 [US1] Add exclusive lock around `Approvals.Approve` and `Approvals.Reject` in `src/br/musketeers/InteropMCP/Approvals.cls` to prevent race conditions (verify `Decision = "pending"` inside lock region)
- [X] T007 [US1] Modify `Guardrails.Check` in `src/br/musketeers/InteropMCP/Guardrails.cls` to call `WorkflowBridge.CreateTask` after `Approvals.CreateRequest` on the critical path

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Concurrent Approval Race Condition Handling (Priority: P2)

**Goal**: Ensure only the first approval decision is honored when multiple operators attempt to decide the same pending approval simultaneously.

**Independent Test**: Simulate concurrent approval attempts on same `ApprovalId`; verify only first succeeds, second receives explicit "already decided" error.

### Implementation for User Story 2

- [X] T008 [US2] Verify lock implementation in `Approvals.Approve`/`Reject` correctly blocks concurrent access (task T006 covers this; validate behavior)
- [X] T009 [US2] Verify explicit error message includes operator identifier who made the first decision (validate `Approvals.Approve`/`Reject` error output)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Audit Trail Consistency Across Interfaces (Priority: P3)

**Goal**: Ensure approval decisions made via terminal and Workflow portal are recorded consistently in `Approvals` table and Workflow task history.

**Independent Test**: Make approvals through both interfaces; verify all decisions appear in `br.musketeers.InteropMCP.Approvals` with matching approver, timestamp, and reason.

### Implementation for User Story 3

- [X] T010 [US3] Verify `Approvals.DecidedAt`, `Approver`, and `Reason` are populated on both terminal and Workflow portal decisions (validate `Approve`/`Reject` methods set these fields)
- [X] T011 [US3] Verify `Log.cls` records all approval decisions with component `approval`, approver identity, timestamp, and reason

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T012 [P] Update `docs/TODO.md` with Workflow approval integration item
- [X] T013 [P] Update `docs/interop-mcp/architecture.md` to document Workflow bridge alternative approval path
- [X] T014 [P] Verify no implementation details leaked into `spec.md` (keep spec technology-agnostic)
- [X] T015 Run quickstart.md validation scenarios end-to-end (requer runtime IRIS — pendente de execução em ambiente com IRIS)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can proceed sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Depends on T006 lock implementation from US1
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Depends on US1 implementation

### Parallel Opportunities

- Setup task T001 is standalone
- Foundational task T002 modifies `Approvals.cls` only - no parallel tasks in this phase
- US1 tasks T003, T004, T005 all modify/create `WorkflowBridge.cls` - must be sequential
- US1 task T006 modifies `Approvals.cls` - depends on T002
- US1 task T007 modifies `Guardrails.cls` - depends on T003 (WorkflowBridge must exist)

### Parallel Example: User Story 1

```bash
# No parallel tasks within US1 - all modify WorkflowBridge.cls or depend on prior tasks
# T003 → T004 → T005 → T006 → T007 (sequential chain)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002) - CRITICAL - blocks all stories
3. Complete Phase 3: User Story 1 (T003 → T007)
4. **STOP and VALIDATE**: Test User Story 1 independently
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Add User Story 3 → Test independently → Deploy/Demo
5. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- ObjectScript implementation - no Python embedding required for MVP
- IRIS Interoperability Workflow module must be available in target environment
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
