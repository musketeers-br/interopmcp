/// Bridge between InteropMCP custom approval mechanism and native IRIS
/// Interoperability Workflow. The Approvals class remains the single source of
/// truth for approval decisions; Workflow tasks are only a UI/assignment layer
/// surfaced in the Management Portal.
Class br.musketeers.InteropMCP.WorkflowBridge Extends %RegisteredObject
{

/// Workflow role that owns the approval tasks. Workflow roles are defined per
/// interoperability-enabled namespace, not per production.
Parameter RoleName = "Operators";

/// External status of a task that nobody has taken yet. Same value as the
/// $$$WfTaskUnassigned macro of EnsWorkflow.inc, which is not reachable from
/// this namespace.
Parameter StatusUnassigned = "Unassigned";

/// Creates an EnsLib.Workflow.Task linked to a pending approval and stores the
/// TaskId on the Approvals record. Never blocks the terminal approval path:
/// if task creation fails, logs a warning and continues.
///
/// The task is created locally, not through a production message flow: the
/// TaskRequest never becomes an Ens.MessageHeader, so there is no deferred
/// response target behind it. The task therefore uses
/// br.musketeers.InteropMCP.WorkflowTaskResponse, which closes the task
/// locally and records the decision in Approvals instead of deferring a
/// response - see docs/ERR_PRODUCTION_MISMATCH_DEFERRED_RESPONSE_ANALYSIS.md.
ClassMethod CreateTask(pApprovalId As %String) As %Status
{
    Set sc = $$$OK
    Try {
        // Look up the approval row
        Set rid = ""
        &sql(SELECT ID INTO :rid FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = :pApprovalId)
        If rid = "" {
            Set sc = $$$ERROR($$$GeneralError, "Approval not found: "_pApprovalId)
            Return sc
        }

        Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(rid)
        If '$IsObject(ap) {
            Set sc = $$$ERROR($$$GeneralError, "Approval not found: "_pApprovalId)
            Return sc
        }
        If ap.Decision '= "pending" {
            Set sc = $$$ERROR($$$GeneralError, "Approval already decided")
            Return sc
        }
        If ap.TaskId '= "" {
            Set sc = $$$ERROR($$$GeneralError, "Task already exists")
            Return sc
        }

        // Workflow role that owns the task
        Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(..#RoleName)
        If '$IsObject(role) {
            Set sc = $$$ERROR($$$GeneralError, "Workflow role not found: "_..#RoleName)
            Return sc
        }

        // The TaskRequest is the workflow request
        Set request = ##class(EnsLib.Workflow.TaskRequest).%New()
        Set request.%Subject = "Approval: "_pApprovalId
        Set request.%Message = "Critical tool invocation approval pending: "_pApprovalId
        Set request.%Priority = 1
        Set request.%Actions = "Approve,Reject"
        Set request.%TaskHandler = "br.musketeers.InteropMCP.WorkflowTaskResponse"
        Set sc = request.%Save()
        If $$$ISERR(sc) Return sc

        // The response the operator acts on. The subclass closes the task
        // locally and records the decision in Approvals.
        Set response = ##class(br.musketeers.InteropMCP.WorkflowTaskResponse).%New()
        Set response.%TaskStatus.Request = request
        Set response.%TaskStatus.Role = role
        Set response.%TaskStatus.IsComplete = 0
        Set response.%Status = ..#StatusUnassigned
        Set response.%RoleName = ..#RoleName
        Set response.%Priority = request.%Priority
        Set response.%Subject = request.%Subject
        Set response.%Message = request.%Message
        Set response.%Actions = request.%Actions
        Set sc = response.%Save()
        If $$$ISERR(sc) Return sc

        // Distribute the task to the worklist so it appears in the
        // IRIS Management Portal / User Portal Workflow Inbox.
        // Non-blocking: if distribution fails, log a warning and
        // keep the approval usable via terminal commands.
        Set count = 0
        Set sc = ##class(EnsLib.Workflow.Engine).SendTaskToAll(response, .count)
        If $$$ISERR(sc) {
            Set logData = ##class(%DynamicObject).%New()
            Do logData.%Set("approval", pApprovalId)
            Do logData.%Set("task", response.%Id())
            Do logData.%Set("distributeTaskError", $System.Status.GetErrorText(sc))
            Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "workflow", "TaskDistributionNonBlocking", logData)
            Set sc = $$$OK
        }

        // Store the generated task ID on the approval
        Set ap.TaskId = response.%Id()
        Set sc = ap.%Save()
        If $$$ISERR(sc) Return sc

        Set logData = ##class(%DynamicObject).%New()
        Do logData.%Set("approval", pApprovalId)
        Do logData.%Set("task", response.%Id())
        Do ##class(br.musketeers.InteropMCP.Log).Write("info", "workflow", "TaskCreated", logData)
    } Catch ex {
        Set sc = ex.AsStatus()
        Set logData = ##class(%DynamicObject).%New()
        Do logData.%Set("approval", pApprovalId)
        Do logData.%Set("error", ex.DisplayString())
        Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "workflow", "TaskCreateFailed", logData)
    }
    Return sc
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
///
/// Tasks created by this bridge run through
/// br.musketeers.InteropMCP.WorkflowTaskResponse.OnAction, the same path the
/// IRIS User Portal action buttons take, so both entry points behave alike.
/// Legacy tasks (plain EnsLib.Workflow.TaskResponse) keep the local
/// completion path: Engine.CompleteTask would call SendDeferredResponse,
/// which fails outside a production message flow.
ClassMethod CompleteTask(pTaskId As %String, pDecision As %String, pApprover As %String, pReason As %String) As %Status
{
    Set sc = $$$OK
    Try {
        Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(pTaskId)
        If '$IsObject(task) {
            Set sc = $$$ERROR($$$GeneralError, "Workflow task not found: "_pTaskId)
            Return sc
        }

        If task.%IsA("br.musketeers.InteropMCP.WorkflowTaskResponse") {
            Set sc = task.OnAction(pDecision, pApprover, pReason)
            Return sc
        }

        // Legacy task: look up the approval linked to this task
        Set rid = ""
        &sql(SELECT ID INTO :rid FROM br_musketeers_InteropMCP.Approvals WHERE TaskId = :pTaskId)
        If rid = "" {
            Set sc = $$$ERROR($$$GeneralError, "No approval linked to Workflow task: "_pTaskId)
            Return sc
        }
        Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(rid)
        If '$IsObject(ap) {
            Set sc = $$$ERROR($$$GeneralError, "No approval linked to Workflow task: "_pTaskId)
            Return sc
        }
        If ap.Decision '= "pending" {
            Return sc  // Idempotent: already decided
        }

        // Open the Workflow TaskResponse and mark it complete.
        Set task.%Action = pDecision
        Set task.%TaskStatus.IsComplete = 1
        Set sc = task.%Save()
        If $$$ISERR(sc) {
            Set logData = ##class(%DynamicObject).%New()
            Do logData.%Set("task", pTaskId)
            Do logData.%Set("error", $System.Status.GetErrorText(sc))
            Do ##class(br.musketeers.InteropMCP.Log).Write("error", "workflow", "TaskSaveFailed", logData)
            Return sc
        }

        // Propagate decision to Approvals (single source of truth)
        If pDecision = "Approve" {
            Set sc = ##class(br.musketeers.InteropMCP.Approvals).Approve(ap.ApprovalId, pApprover)
        } ElseIf pDecision = "Reject" {
            Set sc = ##class(br.musketeers.InteropMCP.Approvals).Reject(ap.ApprovalId, pApprover, pReason)
        } Else {
            Set sc = $$$ERROR($$$GeneralError, "Invalid decision: "_pDecision)
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Return sc
}

}