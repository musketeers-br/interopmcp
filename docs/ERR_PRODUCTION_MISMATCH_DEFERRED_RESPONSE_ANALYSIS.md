# Analysis: Ens.ErrProductionMismatchInDeferredResponse in the InteropMCP approval workflow

> **Companion document.** This file does not replace
> [ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE.md](ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE.md).
> That document describes how the Interoperability Workflow deferred-response
> mechanism works and which system-class options exist. This document records
> the **corrected diagnosis** (with evidence gathered from the running
> instance) and the **fix actually implemented in InteropMCP application code**,
> with no system class touched.

---

## 1. Summary

| | |
|---|---|
| **Symptom** | Clicking *Approve* / *Reject* on a task in the IRIS User Portal raises `Ens.ErrProductionMismatchInDeferredResponse`; the approval stays `pending-approval` forever. |
| **Original diagnosis (wrong)** | The deferred response token carries a production name that differs from `$$$EnsRuntime("Name")` evaluated in the portal CSP context — a context-dependent macro evaluation problem. |
| **Corrected diagnosis** | The deferred response token of the task the operator actually sees is **empty**. There is no context mismatch: there is no token at all. The task was never born inside a production message flow, so it has no deferred-response target. |
| **Fix** | `br.musketeers.InteropMCP.WorkflowTaskResponse` — a subclass of `EnsLib.Workflow.TaskResponse` that overrides `OnAction` and closes the task locally, recording the decision in `br.musketeers.InteropMCP.Approvals`. |
| **System classes changed** | None. `Ens.Host`, `EnsLib.Workflow.Engine` and the rest of the Ensemble library are untouched. |

---

## 2. Corrected root cause

### 2.1 The token is empty, not mismatched

The tasks listed in the operator inbox are the ones created by
`WorkflowBridge.CreateTask`. Inspecting the stored `TaskStatus` of the legacy
tasks (the ones created before the fix):

```
task 86 token=[]                  req=84  status=Assigned    done=0
task 100 token=[]                 req=98  status=Unassigned  done=0
```

`Ens.Host.SendDeferredResponse` parses the token as:

```objectscript
Set tMessageHeaderId=$p(pDeferredResponseToken,"|",1)
Set tProductionName=$p(pDeferredResponseToken,"|",2)
```

With an empty token, `tProductionName` is `""`, which can never equal the name
of the running production — hence `Ens.ErrProductionMismatchInDeferredResponse`.
The error message is about the *token*, not about the production context.

### 2.2 Who fills the token — and who does not

| Component | Behaviour |
|---|---|
| `EnsLib.Workflow.Operation` (the production config item) | Calls `Ens.Host.GetDeferredResponseToken` and passes the result to `EnsLib.Workflow.Engine.%DistributeTask` as `pToken`. This is the **only** place a token is created. |
| `EnsLib.Workflow.Engine.%DistributeTask(pRoleName, pRequest, pToken)` | Receives `pToken` **by value** and stores it in `tTask.%TaskStatus.ResponseToken`. It never generates one. |
| `br.musketeers.InteropMCP.WorkflowBridge.CreateTask` | Creates the `TaskRequest` **locally** — not through a production message flow. There is no `pToken` to hand over, so the token is empty. |

`Ens.Host.GetDeferredResponseToken` builds the token as
`<MessageHeaderId>|<ProductionName>`. The first field is the id of the
`Ens.MessageHeader` that carried the `TaskRequest` into the production, so the
deferred response can be delivered back to the original caller.

### 2.3 The InteropMCP TaskRequest never becomes a message header

The request is built in-process:

```
MetaTools.CreateWorkflowTask
  -> Invocations.CreateInvocation          (row in pending-approval)
  -> Approvals.CreateRequest               (row in pending)
  -> WorkflowBridge.CreateTask             (TaskRequest + TaskResponse, local)
```

`Invoker.Invoke` fires the business service with
`CreateBusinessService` + `ProcessInput` — it does not create an
`Ens.MessageHeader` either. Confirmed on the instance:

```
MessageHeader rows with TaskRequest body: 0
```

**Consequence:** no message header means no deferred-response target. There is
no production to defer the answer to, and no header id to defer it to. This is
structural, not a configuration issue — and it is why none of the "align the
production name" options can work.

### 2.4 Why the portal is the only place that breaks

The terminal path (`Approvals.Approve` / `Approvals.Reject`) never touches the
workflow engine: it updates the approval row and replays the stored invocation
through `Invoker.Invoke`. It works. The portal path goes through
`EnsLib.Workflow.Engine.%ProcessAction` → `TaskResponse.OnAction` →
`Engine.CompleteTask` → `Ens.Host.SendDeferredResponse`, which is where the
empty token explodes.

---

## 3. Additional defects found in the previous implementation

While investigating, three further defects were found in the old
`WorkflowBridge` code. They are fixed as part of this change.

### 3.1 Two task responses were created for one request

The old code called `request.NewResponse(.tTask)` **and** created a second
`TaskResponse` instance by hand, then distributed the second one. The first
(orphan) response stayed in the table forever:

```
task 85  req=84     task 99  req=98      <- orphan responses (forged token)
task 86  req=84     task 100 req=98      <- the ones in the operator inbox
```

### 3.2 `Approvals.TaskId` pointed at the orphan

Because of 3.1, the approval row referenced the response that was **not** in
the worklist. The task the operator sees and the task the approval points at
were two different objects. The end-to-end test now asserts there is exactly
one task response per request and that the approval points at it.

### 3.3 The forged token could hijack an unrelated production message

To work around the error, the old code wrote a hand-built token into
`^EnsRuntime("Name")` and stored `TaskResponseId|<production>` as the response
token:

```
task 85  token=[85|br.musketeers.InteropMCP.Demo.Production]
task 99  token=[99|br.musketeers.InteropMCP.Demo.Production]
```

Two problems:

1. The global is wrong. The real one is `^Ens.Runtime("Name")`
   (`br.musketeers.InteropMCP.Demo.Production`); `^EnsRuntime("Name")` does not
   exist and is always empty. The value was never actually read from there.
2. **The first field of a deferred response token is a `MessageHeader` id.**
   Task 99 forged the id `99`, and `Ens.MessageHeader` id 99 is a real,
   unrelated message:

   ```
   header 99: body=br.musketeers.InteropMCP.Demo.CustomerUpdateRequest
               src=AuditProcess tgt=AuditOperation
   ```

   Approving that task would have delivered the workflow response as a
   deferred answer to somebody else's `CustomerUpdate` message — cross-talk
   between unrelated flows, and a silent loss of the approval result. This is
   worse than the original error and is the reason the token is now simply
   left empty and never forged.

---

## 4. The fix

### 4.1 `br.musketeers.InteropMCP.WorkflowTaskResponse` (new)

A subclass of `EnsLib.Workflow.TaskResponse` that overrides `OnAction`:

```objectscript
Method OnAction(pAction As %String, pApprover As %String = "", pReason As %String = "") As %Status
```

* Resolves the acting user (explicit argument → task ownership → session user).
* Finds the approval gated by this task and records the decision through
  `Approvals.Approve` / `Approvals.Reject` — the single source of truth.
* Closes the task locally, replicating the bookkeeping of
  `EnsLib.Workflow.Engine.CompleteTask` **minus** the `SendDeferredResponse`
  call: `%UserName`, `%RoleName`, `%UserTitle`, `%UserRanking`, `%Action`,
  `%Status = "Completed"`, `TaskStatus.IsComplete = 1`,
  `TaskStatus.TimeCompleted`, and the deletion of the worklist rows.
* Saves the task.

The subclass adds no properties, so the compiler generates the inherited
persistent storage (`Storage Default { <Type>%Storage.Persistent</Type> }`).
The rows live in the parent's table, `EnsLib_Workflow.TaskResponse`, which is
why `EnsLib.Workflow.Engine` can open them polymorphically.

### 4.2 `WorkflowBridge.CreateTask` (rewritten)

* Creates **one** `TaskRequest` and **one** `WorkflowTaskResponse`.
* Sets `%TaskHandler` to the subclass class name.
* Sets `TaskStatus.Role` and `TaskStatus.Request` explicitly.
* Distributes with `EnsLib.Workflow.Engine.SendTaskToAll` (the same call the
  stock `OnNewTask` path uses).
* Stores the id of the response that is actually in the worklist on the
  approval row.

No token is written anywhere, and the `^EnsRuntime` global is no longer
touched.

### 4.3 `WorkflowBridge.CompleteTask` (rewritten)

* For tasks of the new subclass, delegates to the same `OnAction` the portal
  uses — both entry points now behave identically.
* Keeps a local completion path for **legacy** tasks (plain
  `EnsLib.Workflow.TaskResponse`), because `Engine.CompleteTask` would call
  `SendDeferredResponse` on them and fail.

### 4.4 Why the portal buttons work against the subclass

`EnsLib.Workflow.Engine.%ProcessAction` opens the task polymorphically and
calls the method on the concrete class:

```objectscript
Set tTask = ##class(EnsLib.Workflow.TaskResponse).%OpenId(tItem.TaskGetObjectId(),4,.tSC)
...
Set tSC = tTask.OnAction(pActionId)
```

`OnAction` is dispatched on the *stored* class, so the subclass override runs.
The portal passes only the action id; the operator identity is taken from the
task ownership (`TaskStatus.AssignedTo`), which the portal sets through
`%TakeOwnershipForTask` before the action is submitted.

---

## 5. Namespace constraint: `Include` does not work in `IRISAPP`

The workflow macros (`$$$WfTaskCompleted`, `$$$WfTaskUnassigned`,
`$$$timeUTC`) live in `Ensemble.inc` / `EnsWorkflow.inc`, which are pulled in
with `Include (Ensemble, EnsWorkflow)`. **That directive does not compile in
the `IRISAPP` namespace** — every variant fails:

```
ERROR #5559: The class definition for class '...ZzProbeA' could not be parsed
correctly, possibly due to non-matching {} or () characters or a missing ;
character or non-matched /* */ blocks.
```

Tested and rejected: `Include (Ensemble)`, `Include (EnsWorkflow)`,
`Include (Ensemble, EnsWorkflow)`, and `Include Ensemble` without
parentheses. A class **without** any `Include` compiles fine, and the rest of
the project already follows that rule.

The fix therefore avoids the macros:

| Macro | Replacement used in the code |
|---|---|
| `$$$WfTaskCompleted` | `Parameter StatusCompleted = "Completed"` |
| `$$$WfTaskUnassigned` | `Parameter StatusUnassigned = "Unassigned"` |
| `$$$timeUTC` | `##class(Ens.DataType.UTC).timeUTC()` |

The two status values are the literal values of the macros in
`EnsWorkflow.inc`; the timestamp helper is the public class method the macro
expands to. The parameters are documented in the class so the provenance stays
visible.

---

## 6. Verification

`src/br/musketeers/InteropMCP/TestWorkflowFix.cls` drives the **real** call
chain the portal uses — `Engine.%TakeOwnershipForTask` then
`Engine.%ProcessAction` — against a held invocation created through the
production entry point (`MetaTools.CreateWorkflowTask`).

Run it with:

```objectscript
Do ##class(br.musketeers.InteropMCP.TestWorkflowFix).Run()
```

Scenarios covered:

1. **Portal / Approve** — ownership taken, action processed, approval
   `approved`, invocation replayed and `completed`, task closed, worklist row
   removed.
2. **Portal / Reject** — approval `rejected` with a reason, invocation
   `rejected`, task closed, worklist row removed.
3. **Terminal / Approve** — `WorkflowBridge.CompleteTask` drives the same
   `OnAction`, records the explicit approver, and releases the invocation.

Every scenario also asserts that exactly one task response exists per request
and that the approval points at the task shown in the inbox.

Result on the running instance (IRIS 2026.3.0AI, namespace `IRISAPP`):

```
=== WORKFLOW TASK COMPLETION TEST ===
-- portal action: approve --
  [ OK ] held invocation created
  [ OK ] task id stored on the approval
  [ OK ] task opens polymorphically
  [ OK ] task uses WorkflowTaskResponse
  [ OK ] exactly one task response per request (got 1)
  [ OK ] task listed in the operator worklist
  [ OK ] portal action succeeded without ErrProductionMismatchInDeferredResponse
  [ OK ] task marked complete
  [ OK ] task action recorded (got Approve)
  [ OK ] task removed from the worklist
  [ OK ] approval approved (got approved)
  [ OK ] approver recorded (got _SYSTEM)
  [ OK ] invocation completed (got completed)
-- portal action: reject --
  ... (all OK)
-- terminal action: approve --
  ... (all OK)
=== RESULT: ALL CHECKS PASSED ===
```

---

## 7. Options from the original document that were dropped

| Original option | Why it was dropped |
|---|---|
| **Option A** — align `$$$EnsRuntime("Name")` in the CSP context | The token is empty; aligning a production name cannot create a token. It would also require writing to system globals. |
| **Option B** — make `SendDeferredResponse` tolerant of mismatches | Would patch a system class to accommodate a task that has no deferred response target at all. The response would still have nowhere to go. |
| **Option C** — add an opt-out flag to `TaskRequest` / `TaskResponse` | Also a system-class change. The same effect is obtained from application code by subclassing `TaskResponse` and overriding `OnAction`. |

The remaining option — keeping the native `EnsLib.Workflow.Operation` in the
production so that real messages carry real tokens — is the correct design for
workflows whose requests arrive as production messages. It was not selected
here because the InteropMCP request is created locally, outside any message
flow, and adding a production configuration item would not create the missing
`Ens.MessageHeader`.

---

## 8. Legacy tasks

Tasks created **before** this fix are stored as plain
`EnsLib.Workflow.TaskResponse` objects. The portal opens them polymorphically
and dispatches to the stock `OnAction`, so the *Approve* / *Reject* buttons on
those rows still raise `Ens.ErrProductionMismatchInDeferredResponse`. The
override cannot retroactively change the class of an existing row.

They can still be decided from the terminal:

```objectscript
Do ##class(br.musketeers.InteropMCP.Approvals).Approve("<ApprovalId>", "<User>")
Do ##class(br.musketeers.InteropMCP.Approvals).Reject("<ApprovalId>", "<User>", "<Reason>")
```

which is also the documented fallback in
[ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE.md](ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE.md).

Note that for the legacy rows the approval points at the **orphan** task
(section 3.2), so `WorkflowBridge.CompleteTask` cannot clean the corresponding
worklist entry — the terminal decision plus a manual removal of the stale
worklist row is required.

### 8.1 Legacy cleanup performed on 2026-11-11

The instance carried 5 approvals still in `pending-approval` (all of them
gating a `RiskCheck` against the test CNPJ `12.345.678/0001-90`, created by
the pre-fix code) and 13 legacy tasks occupying 23 worklist rows.

They were cleared as follows:

* The 5 pending approvals were **rejected** through
  `Approvals.Reject` (the terminal path). A rejection never releases the
  gated invocation, so no business service was executed.
* The 23 worklist rows of the 13 legacy tasks (ids 20, 24, 31, 38, 40, 51,
  58, 65, 72, 79, 86, 93, 100) were deleted.

Result: 0 approvals in `pending-approval`, 0 rows in the operator inbox. The
legacy `TaskResponse` rows themselves were kept — they are the workflow
history and are still visible in the Tasklist view.

---

## 9. Files

| File | Role |
|---|---|
| `src/br/musketeers/InteropMCP/WorkflowTaskResponse.cls` | New subclass with the `OnAction` override (local completion + decision recording). |
| `src/br/musketeers/InteropMCP/WorkflowBridge.cls` | `CreateTask` and `CompleteTask` rewritten: single task, correct `TaskId`, no forged token. |
| `src/br/musketeers/InteropMCP/TestWorkflowFix.cls` | End-to-end test of the portal and terminal paths. |
| `src/br/musketeers/InteropMCP/Approvals.cls` | Unchanged — source of truth for the decisions. |
| `src/br/musketeers/InteropMCP/MetaTools.cls` | Unchanged — MCP entry point that holds the call. |
| `docs/ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE.md` | Unchanged — original analysis of the system-class mechanism. |
