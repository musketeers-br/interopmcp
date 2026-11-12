/// Task response used by the InteropMCP approval workflow.
///
/// The stock EnsLib.Workflow.TaskResponse completes a task by calling
/// EnsLib.Workflow.Engine.CompleteTask, which always forwards the result
/// through Ens.Host.SendDeferredResponse. That call needs a deferred response
/// token of the form <MessageHeaderId>|<ProductionName>: the first part is the
/// header of the message that carried the TaskRequest into the production.
///
/// InteropMCP tasks are not born inside a production message flow: the
/// TaskRequest is built locally by WorkflowBridge and never becomes an
/// Ens.MessageHeader, so there is no header to defer a response to and no
/// production to defer it to. Sending a token anyway makes
/// SendDeferredResponse fail with
/// Ens.ErrProductionMismatchInDeferredResponse (an empty token production
/// name never matches the running production), and a hand-built token whose
/// first part is a TaskResponse id is worse than useless: that id is read back
/// as a MessageHeader id and can collide with an unrelated production message.
///
/// This subclass therefore overrides the completion path: the operator action
/// is recorded in br.musketeers.InteropMCP.Approvals (the single source of
/// truth for approval decisions) and the task is closed locally, reusing the
/// bookkeeping of the workflow engine but skipping the deferred response.
/// The IRIS User Portal action buttons work against this class because
/// EnsLib.Workflow.Engine.%ProcessAction opens the task polymorphically and
/// calls OnAction on the concrete class.
Class br.musketeers.InteropMCP.WorkflowTaskResponse Extends EnsLib.Workflow.TaskResponse
{

/// External status of a completed task. Same value as the $$$WfTaskCompleted
/// macro of EnsWorkflow.inc, which is not reachable from this namespace.
Parameter StatusCompleted = "Completed";

/// Called by the workflow engine when an operator acts on this task.
/// pAction is the action button pressed (Approve, Reject, ...).
/// pApprover and pReason are optional: the portal passes neither, so the
/// acting user is resolved from the task ownership; the terminal path
/// (WorkflowBridge.CompleteTask) passes both explicitly.
Method OnAction(pAction As %String, pApprover As %String = "", pReason As %String = "") As %Status
{
    Set tSC = $$$OK
    Try {
        Set tTaskId = ..%Id()

        // Resolve the acting user: explicit caller, then task ownership, then
        // the authenticated session user.
        Set tApprover = pApprover
        If tApprover = "" Set tApprover = ..%TaskStatus.AssignedTo
        If tApprover = "" Set tApprover = ..%UserName
        If tApprover = "" Set tApprover = $USERNAME

        // Resolve the approval gated by this task. The decision is recorded
        // first: if it cannot be recorded the task stays open so the operator
        // can retry the action.
        Set tApprovalId = ""
        Set tDecision = ""
        &sql(SELECT ApprovalId, Decision INTO :tApprovalId, :tDecision FROM br_musketeers_InteropMCP.Approvals WHERE TaskId = :tTaskId)
        If SQLCODE = 0 {
            If tDecision = "pending" {
                Set tAction = $ZConvert(pAction, "L")
                If tAction = "approve" {
                    Set tSC = ##class(br.musketeers.InteropMCP.Approvals).Approve(tApprovalId, tApprover)
                } ElseIf tAction = "reject" {
                    Set tReason = pReason
                    If tReason = "" Set tReason = "Rejected through the workflow portal by "_tApprover
                    Set tSC = ##class(br.musketeers.InteropMCP.Approvals).Reject(tApprovalId, tApprover, tReason)
                } Else {
                    Set tSC = $$$ERROR($$$GeneralError, "Invalid workflow action: "_pAction)
                }
                If $$$ISERR(tSC) Return tSC
            }
        } Else {
            // No approval is linked to this task: it still leaves the inbox,
            // but there is nothing to decide.
            Set logData = ##class(%DynamicObject).%New()
            Do logData.%Set("task", tTaskId)
            Do logData.%Set("action", pAction)
            Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "workflow", "TaskWithoutApproval", logData)
        }

        // Close the task locally. This is the bookkeeping of
        // EnsLib.Workflow.Engine.CompleteTask without the deferred response.
        Set tStatus = ..%TaskStatus
        Set ..%UserName = tApprover
        If $IsObject(tStatus.Role) {
            Set ..%RoleName = tStatus.Role.Name
            Set tMember = ##class(EnsLib.Workflow.RoleMembership).%OpenId(..%RoleName _ "||" _ tApprover)
            If $IsObject(tMember) {
                Set ..%UserTitle = tMember.Title
                Set ..%UserRanking = tMember.Ranking
            }
        }
        Set ..%Action = pAction
        Set ..%Status = ..#StatusCompleted
        Set tStatus.IsComplete = 1
        Set tStatus.TimeCompleted = ##class(Ens.DataType.UTC).timeUTC()

        // Remove the task from the worklist of every role member.
        &sql(DELETE FROM EnsLib_Workflow.Worklist WHERE Task = :tTaskId)
        If SQLCODE < 0 {
            Set tSC = $$$ERROR($$$GeneralError, "While completing a workflow task, delete from Worklist failed with SQLCODE "_SQLCODE)
            Return tSC
        }

        Set tSC = ..%Save()
        If $$$ISERR(tSC) Return tSC

        Set logData = ##class(%DynamicObject).%New()
        Do logData.%Set("task", tTaskId)
        Do logData.%Set("action", pAction)
        Do logData.%Set("approver", tApprover)
        Do ##class(br.musketeers.InteropMCP.Log).Write("info", "workflow", "TaskCompleted", logData)
    } Catch ex {
        Set tSC = ex.AsStatus()
    }
    Return tSC
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
