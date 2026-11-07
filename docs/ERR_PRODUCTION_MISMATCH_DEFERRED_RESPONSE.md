# Error: Ens.ErrProductionMismatchInDeferredResponse

## Summary

The IRIS Interoperability workflow portal (`%DeepSee.UserPortal.Workflow`) triggers `Ens.Host.SendDeferredResponse` when an operator completes a workflow approval task. This method compares the production name stored in the deferred response token against `$$$EnsRuntime("Name")` evaluated in the CSP context of the portal. When these values differ, `Ens.ErrProductionMismatchInDeferredResponse` is raised and the approval is not processed.

## Symptom

- A critical tool invocation (e.g. `RiskCheck`) remains in `pending-approval` state.
- The operator clicks **Approve** in the IRIS Management Portal / User Portal workflow inbox.
- Error `Ens.ErrProductionMismatchInDeferredResponse: Production name mismatch while sending deferred response` is written to the Event Log.
- The invocation stays stuck in `pending-approval` indefinitely.

## Root Cause

The system class `EnsLib.Workflow.Engine` method `CompleteTask` **always** calls `##class(Ens.Host).SendDeferredResponse`. There is no flag or configuration to disable the deferred response.

The deferred response token is generated in `EnsLib.Workflow.Engine.%DistributeTask` via `Ens.Host.GetDeferredResponseToken`, which builds the token as:

```
MessageHeaderId | $$$EnsRuntime("Name")
```

Later, when the operator submits the approval through the portal (`%DeepSee.UserPortal.Workflow.zen`), the call chain is:

```
%DeepSee.UserPortal.Workflow.%OnSubmit
  -> %DeepSee.UserPortal.Workflow.FormEngine.%OnSubmit
    -> EnsLib.Workflow.Engine.%ProcessAction
      -> EnsLib.Workflow.TaskResponse.OnAction
        -> EnsLib.Workflow.TaskResponse.CompleteTask
          -> EnsLib.Workflow.Engine.CompleteTask
            -> Ens.Host.SendDeferredResponse
```

Inside `Ens.Host.SendDeferredResponse`:

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
    }
}
```

The macro `$$$EnsRuntime("Name")` returns **different values depending on the execution context**:
- At task creation time (interop namespace context): captures the running production name.
- At task completion time (CSP portal context): returns a different or empty value, causing the mismatch.

## Affected InterSystems Classes

| Class | Method | Role |
|-------|--------|------|
| `Ens.Host` | `SendDeferredResponse` | Compares token production name vs `$$$EnsRuntime("Name")`; raises the error. |
| `Ens.Host` | `GetDeferredResponseToken` | Builds the token `MessageHeaderId|$$$EnsRuntime("Name")`. |
| `EnsLib.Workflow.Engine` | `CompleteTask` | Unconditionally calls `SendDeferredResponse`; no way to opt out. |
| `EnsLib.Workflow.TaskResponse` | `CompleteTask` / `OnAction` | Entry point called by the portal form submission. |

## Error Location in Source

`Ens.Host.cls`, method `SendDeferredResponse` (approximately lines 711-741). The critical comparison is:

```objectscript
If (tProductionName '= tCurrentProduction) {
    Set tSC=$$$EnsError($$$EnsErrProductionMismatchInDeferredResponse)
    Quit
}
```

## Stack Trace Observed

```
e^EnsError+1^Ens.Util.Error.1^1
e^SendDeferredResponse+11^Ens.Host.1^1
e^CompleteTask+33^EnsLib.Workflow.Engine.1^1
e^CompleteTask+1^EnsLib.Workflow.TaskResponse.1^1
e^OnAction+2^EnsLib.Workflow.TaskResponse.1^1
e^%ProcessAction+18^EnsLib.Workflow.Engine.1^1
e^%OnSubmit+43^EnsLib.Workflow.FormEngine.1^1
e^%OnSubmit+4^%DeepSee.UserPortal.Workflow.1^1
e^OnPreHTTP+89^%ZEN.Controller.1^1
e^OnPreHTTP+1^%ZEN.Component.abstractPage.1^1
e^Page+7^%DeepSee.UserPortal.standardPage.1^1
e^CSPDispatch+531^%SYS.cspServer^1
```

## Workaround (Non-System Code)

Approval can be performed outside the workflow portal, avoiding `SendDeferredResponse` entirely:

```objectscript
Do ##class(br.musketeers.InteropMCP.Approvals).Approve("<ApprovalId>", "<User>")
```

This path updates the approval record and releases the invocation without touching `Ens.Host.SendDeferredResponse`.

## Required Namespace for Testing Corrections to InterSystems Classes

To test and apply corrections to the InterSystems system classes involved (`Ens.Host.cls`, `EnsLib.Workflow.Engine.cls`, and related workflow engine classes), access is required to:

| Namespace | Purpose |
|-----------|---------|
| `%SYS` | System classes (`Ens.Host`, `Ens.Director`, `$$$EnsRuntime` macro definition), system globals (`^%SYS`, `^EnsRuntime`), and compilation of system library classes. |
| `IRISAPP` (or the production's namespace) | Testing the production runtime, verifying `$$$EnsRuntime("Name")` in the production context, and validating end-to-end deferred response behavior. |

**Primary namespace for system-class correction: `%SYS`.**

## Correction Plan

### 1. Investigate `$$$EnsRuntime("Name")` Context Discrepancy

Confirm what `$$$EnsRuntime("Name")` returns in:
- The interop namespace context where tasks are created.
- The CSP portal context where `%DeepSee.UserPortal.Workflow` runs.

If the values differ, the fix must align them so `SendDeferredResponse` receives matching production names.

### 2. Option A: Align `$$$EnsRuntime("Name")` in CSP Context

Ensure that the global or mechanism backing `$$$EnsRuntime("Name")` returns the running production name consistently in the portal CSP session. This may require setting or persisting `^EnsRuntime("Name")` (or the equivalent system global) in `%SYS` so the CSP portal sees the same production name as the interop namespace.

### 3. Option B: Make `SendDeferredResponse` Tolerant of Context Mismatch

Modify `Ens.Host.SendDeferredResponse` to fall back to `##class(Ens.Director).GetCurrProductionName()` (or equivalent) when `$$$EnsRuntime("Name")` does not match the token, rather than hard-failing. This makes the deferred response robust against context-dependent macro evaluation.

### 4. Option C: Allow Opt-Out of Deferred Response in Workflow Engine

Add a flag or property to `EnsLib.Workflow.TaskRequest` / `EnsLib.Workflow.TaskResponse` (e.g. `%DeferredResponse`) that, when set to 0, causes `EnsLib.Workflow.Engine.CompleteTask` to skip the call to `Ens.Host.SendDeferredResponse` and simply mark the task complete locally. This gives application code control over whether a deferred response is expected.

### 5. Validate the Fix

1. Compile modified system classes in `%SYS`.
2. Restart the production in `IRISAPP`.
3. Create a new critical tool invocation (e.g. `RiskCheck`).
4. Approve via the portal (`%DeepSee.UserPortal.Workflow.zen`).
5. Confirm:
   - No `Ens.ErrProductionMismatchInDeferredResponse` in Event Log.
   - Invocation status transitions from `pending-approval` to `completed`.
   - Deferred response is delivered without error.

---

**Note:** This document focuses exclusively on InterSystems system classes. Project-specific classes are referenced only where they interact with the system classes described above.