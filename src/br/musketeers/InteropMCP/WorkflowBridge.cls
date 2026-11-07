/// Bridge between InteropMCP custom approval mechanism and native IRIS
/// Interoperability Workflow. The Approvals class remains the single source of
/// truth for approval decisions; Workflow tasks are only a UI/assignment layer
/// surfaced in the Management Portal.
Class br.musketeers.InteropMCP.WorkflowBridge Extends %RegisteredObject
{

/// Creates an EnsLib.Workflow.Task linked to a pending approval and stores the
/// TaskId on the Approvals record. Never blocks the terminal approval path:
/// if task creation fails, logs a warning and continues.
ClassMethod CreateTask(pApprovalId As %String) As %Status
{
    Set sc = $$$OK
    Try {
        // Look up the approval row
        Set rid = ""
        &sql(SELECT ID INTO :rid FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = :pApprovalId)
        If rid = "" {
            Set sc = $$$ERROR($$$GeneralError, "Approval not found: "_pApprovalId)
        } Else {
            Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(rid)
            If $IsObject(ap) {
                If ap.Decision '= "pending" {
                    Set sc = $$$ERROR($$$GeneralError, "Approval already decided")
                } ElseIf ap.TaskId '= "" {
                    Set sc = $$$ERROR($$$GeneralError, "Task already exists")
                } Else {
                    // Create the Workflow TaskRequest
                    Set request = ##class(EnsLib.Workflow.TaskRequest).%New()
                    Set request.%Subject = "Approval: "_pApprovalId
                    Set request.%Message = "Critical tool invocation approval pending: "_pApprovalId
                    Set request.%Priority = 1
                    Set request.%Actions = "Approve,Reject"
                    // NOTE: %DeferredResponse no longer exists on EnsLib.Workflow.TaskRequest
                    // (IRIS 2026.x). The production mismatch is handled below by overriding
                    // %TaskStatus.ResponseToken with the current production name.

                    // Create the TaskResponse from the request
                    Set sc = request.NewResponse(.response)
                    If $$$ISERR(sc) {
                    } Else {
                        // Link the TaskResponse to the original request (required)
                        Set response.%TaskStatus.Request = request

                        // Try to assign to a role if one exists
                        Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId("Operators")
                        If $IsObject(role) {
                            Set response.%TaskStatus.Role = role
                        }
                        Set response.%TaskStatus.IsComplete = 0

                        Set sc = response.%Save()
                        If $$$ISERR(sc) {
                        } Else {
                            // Distribute the task to the worklist so it appears in the
                            // IRIS Management Portal / User Portal Workflow Inbox.
                            // Non-blocking: if distribution fails, log a warning and
                            // keep the approval usable via terminal commands.
                            Set token = ""
                            Set sc = ##class(EnsLib.Workflow.Engine).%DistributeTask("Operators", request, .token)
                            If $$$ISERR(sc) {
                                Set logData = ##class(%DynamicObject).%New()
                                Do logData.%Set("approval", pApprovalId)
                                Do logData.%Set("task", response.%Id())
                                Do logData.%Set("distributeTaskError", $System.Status.GetErrorText(sc))
                                Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "workflow", "TaskDistributionNonBlocking", logData)
                                Set sc = $$$OK
                            } Else {
                                // Override ResponseToken with current production name to avoid
                                // ErrProductionMismatchInDeferredResponse when portal calls
                                // SendDeferredResponse via EnsLib.Workflow.Engine.CompleteTask.
                                Set prodName = $Get(^EnsRuntime("Name"),"")
                                If prodName = "" Set prodName = "br.musketeers.InteropMCP.Demo.Production"
                                Set response.%TaskStatus.ResponseToken = response.%Id()_"|"_prodName
                                Set sc = response.%Save()
                            }

                            // Store the generated task ID on the approval
                            Set ap.TaskId = response.%Id()
                            Set sc = ap.%Save()
                            If $$$ISERR(sc) {
                            } Else {
                                Set logData = ##class(%DynamicObject).%New()
                                Do logData.%Set("approval", pApprovalId)
                                Do logData.%Set("task", response.%Id())
                                Do ##class(br.musketeers.InteropMCP.Log).Write("info", "workflow", "TaskCreated", logData)
                            }
                        }
                    }
                }
            }
        }
    } Catch ex {
        Set sc = ex.AsStatus()
        Set logData = ##class(%DynamicObject).%New()
        Do logData.%Set("approval", pApprovalId)
        Do logData.%Set("error", ex.DisplayString())
        Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "workflow", "TaskCreateFailed", logData)
    }
    Quit sc
}

/// Returns pending approvals that do not yet have a linked Workflow task.
ClassMethod ListPendingTasks(Output pList As %DynamicObject) As %Status
{
    Set pending = ##class(%DynamicArray).%New()
    Set id = ""
    For {
        Set id = $Order(^InteropMCP.ApprovalsD(id))
        If id = "" Quit
        Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(id)
        If $IsObject(ap) {
            If (ap.Decision = "pending") && (ap.TaskId = "") {
                Do pending.%Push(ap.ApprovalId)
            }
        }
    }
    Set pList = ##class(%DynamicObject).%New()
    Do pList.%Set("pending", pending)
    Quit $$$OK
}

/// Completes a Workflow task and propagates the decision to Approvals.Approve
/// or Approvals.Reject. Idempotent: a task already completed does not trigger
/// a new replay of the invocation.
ClassMethod CompleteTask(pTaskId As %String, pDecision As %String, pApprover As %String, pReason As %String) As %Status
{
    Set sc = $$$OK
    Try {
        // Look up the approval linked to this task
        Set rid = ""
        &sql(SELECT ID INTO :rid FROM br_musketeers_InteropMCP.Approvals WHERE TaskId = :pTaskId)
        If rid = "" {
            Set sc = $$$ERROR($$$GeneralError, "No approval linked to Workflow task: "_pTaskId)
        } Else {
            Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(rid)
            If $IsObject(ap) {
                If ap.Decision '= "pending" {
                    Set sc = $$$OK  // Idempotent: already decided
                } Else {
                    // Open the Workflow TaskResponse and mark it complete.
                    // Alternative A: set %Action + IsComplete directly instead of
                    // calling task.CompleteTask() -> Engine.CompleteTask() ->
                    // SendDeferredResponse, which fails outside a production context
                    // (ErrProductionMismatchInDeferredResponse).
                    Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(pTaskId)
                    If $IsObject(task) {
                        Set task.%Action = pDecision
                        Set task.%TaskStatus.IsComplete = 1
                        Set sc = task.%Save()
                        If $$$ISERR(sc) {
                            Set logData = ##class(%DynamicObject).%New()
                            Do logData.%Set("task", pTaskId)
                            Do logData.%Set("error", $System.Status.GetErrorText(sc))
                            Do ##class(br.musketeers.InteropMCP.Log).Write("error", "workflow", "TaskSaveFailed", logData)
                        } Else {
                            // Propagate decision to Approvals (single source of truth)
                            If pDecision = "Approve" {
                                Set sc = ##class(br.musketeers.InteropMCP.Approvals).Approve(ap.ApprovalId, pApprover)
                            } ElseIf pDecision = "Reject" {
                                Set sc = ##class(br.musketeers.InteropMCP.Approvals).Reject(ap.ApprovalId, pApprover, pReason)
                            } Else {
                                Set sc = $$$ERROR($$$GeneralError, "Invalid decision: "_pDecision)
                            }
                        }
                    } Else {
                        Set sc = $$$ERROR($$$GeneralError, "Workflow task not found: "_pTaskId)
                    }
                }
            }
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

}