# Required InterSystems System Class Fixes

## Summary
This document describes the required fixes to InterSystems IRIS system classes to resolve `Ens.ErrProductionMismatchInDeferredResponse` when approving workflow tasks via the CSP portal (`%DeepSee.UserPortal.Workflow`).

## Root Cause
The CSP portal context (`%DeepSee.UserPortal.Workflow.zen`) evaluates `$$$EnsRuntime("Name")` differently than the interop namespace context where workflow tasks are created. When the portal's `EnsLib.Workflow.Engine.CompleteTask` calls `Ens.Host.SendDeferredResponse`, the production name comparison fails because:
- Token contains production name from interop context (e.g., `br.musketeers.InteropMCP.Demo.Production`)
- CSP portal context returns a different/empty value for `$$$EnsRuntime("Name")`

## Affected System Classes

### 1. `Ens.Host` (in `Ens.Host.cls`)
**Method:** `SendDeferredResponse`

**Current problematic code (lines ~711-741):**
```objectscript
ClassMethod SendDeferredResponse(pDeferredResponseToken As %String, pResponse As %Library.Persistent) As %Status
{
    Set tSC=$$$OK
    Try {
        Set tMessageHeaderId=$p(pDeferredResponseToken,"|",1)
        Set tProductionName=$p(pDeferredResponseToken,"|",2)
        Set tCurrentProduction=$g($$$EnsRuntime("Name")) 
        If (tCurrentProduction = "") || '##class(Ens.Director).IsProductionRunning() {
            Set tSC=$$$EnsError($$$EnsErrProductionNotRunning)
            Quit
        }
        If (tProductionName '= tCurrentProduction) {
            Set tSC=$$$EnsError($$$EnsErrProductionMismatchInDeferredResponse)
            Quit
        }
        ...
```

**Proposed fix:** Convert the hard error to a warning and proceed with delivery when production is running.

```objectscript
        If (tProductionName '= tCurrentProduction) {
            // Production name mismatch between token and runtime context.
            // The production IS running, so proceed with delivery instead of
            // hard-failing. This handles contexts (e.g. CSP portal) where
            // $$$EnsRuntime("Name") differs from the production name stored
            // in the deferred response token.
            $$$LOGWARNING("Production name mismatch in deferred response: token="_tProductionName_" runtime="_tCurrentProduction_" - proceeding with delivery")
        }
```

### 2. `EnsLib.Workflow.Engine` (in `EnsLib.Workflow.Engine.cls`)
**Method:** `CompleteTask`

**Current code:**
```objectscript
ClassMethod CompleteTask(pTask As EnsLib.Workflow.TaskResponse, pAction As %String = "") As %Status
{
    ...
    // return task as response to caller
    Set tSC = ##class(Ens.Host).SendDeferredResponse(tStatus.ResponseToken, pTask)
    If $$$ISERR(tSC) Quit
    ...
}
```

**Proposed fix:** Add opt-out mechanism via `%DeferredResponse` property on TaskRequest/TaskResponse.

```objectscript
    // return task as response to caller, unless deferred response is disabled
    Set tSkipDeferred = $Get(pTask.%TaskStatus.Request.%DeferredResponse,1)
    If 'tSkipDeferred {
        Set tSC = ##class(Ens.Host).SendDeferredResponse(tStatus.ResponseToken, pTask)
        If $$$ISERR(tSC) Quit
    }
```

**Also requires:** Add `%DeferredResponse` property to `EnsLib.Workflow.TaskRequest` class:
```objectscript
Property %DeferredResponse As %Boolean [ InitialExpression = 1 ];
```

## Impact
- Low risk: Changes only affect deferred response error handling
- Backward compatible: Existing behavior preserved when names match
- Fixes CSP portal workflow approval for interop productions

## Testing
1. Create critical tool invocation requiring approval
2. Approve via CSP portal (`%DeepSee.UserPortal.Workflow.zen`)
3. Verify no `Ens.ErrProductionMismatchInDeferredResponse` in Event Log
4. Verify invocation transitions from `pending-approval` to `completed`

## Current Workaround (Implemented in Application Code)
Since system classes cannot be modified in this instance, the application implements a fix in `br.musketeers.InteropMCP.WorkflowBridge` and a new subclass `br.musketeers.InteropMCP.WorkflowTaskResponse`:

1. **`WorkflowTaskResponse` subclass** — Overrides `OnAction` to record the decision in `Approvals` and close the task locally, replicating the bookkeeping of `Engine.CompleteTask` **without** calling `Ens.Host.SendDeferredResponse`. The portal dispatches to this `OnAction` polymorphically, so **portal approval works for tasks created via this subclass**.
2. **`WorkflowBridge.CreateTask` rewritten** — Creates exactly one `TaskRequest` + one `WorkflowTaskResponse`; sets `%TaskHandler` to the subclass; distributes via `Engine.SendTaskToAll`; stores the correct `TaskId` on the approval. **No token is forged** — the previous approach of hand-building a `ResponseToken` was a defect that could hijack an unrelated `Ens.MessageHeader` (see `docs/ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE_ANALYSIS.md` §3.3).
3. **`WorkflowBridge.CompleteTask` rewritten** — For tasks of the new subclass, delegates to the same `OnAction` the portal uses; for legacy tasks (plain `EnsLib.Workflow.TaskResponse`), keeps a local completion path that avoids `SendDeferredResponse`.
4. **Direct approval API** — `Approvals.Approve`/`Reject` bypass the workflow engine entirely and work reliably (terminal fallback / headless operator).

**Status:** Portal approval **now works** for tasks created by the current `WorkflowBridge` (using `WorkflowTaskResponse`). Legacy tasks (created before this fix) still fail via portal with `Ens.ErrProductionMismatchInDeferredResponse`; use the terminal path `Approvals.Approve`/`Reject` for those.

## Files to Submit to InterSystems
- Modified `Ens.Host.cls` (SendDeferredResponse fix)
- Modified `EnsLib.Workflow.Engine.cls` (CompleteTask opt-out)
- Modified `EnsLib.Workflow.TaskRequest.cls` (%DeferredResponse property)

## References
- Error: `Ens.ErrProductionMismatchInDeferredResponse`
- Stack trace: `SendDeferredResponse+11^Ens.Host.1` → `CompleteTask+33^EnsLib.Workflow.Engine.1`
- Portal: `%DeepSee.UserPortal.Workflow.zen`