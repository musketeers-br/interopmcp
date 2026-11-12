/// End-to-end test for the workflow task completion path.
///
/// Covers the regression that broke the IRIS User Portal action buttons with
/// Ens.ErrProductionMismatchInDeferredResponse: the task shown in the inbox
/// carried no deferred response token, so the workflow engine refused to close
/// it and the approval stayed pending forever.
///
/// The fix routes the completion through
/// br.musketeers.InteropMCP.WorkflowTaskResponse.OnAction, which records the
/// decision in Approvals and closes the task locally. The test drives the
/// exact call chain the portal uses
/// (Engine.%TakeOwnershipForTask -> Engine.%ProcessAction) and asserts the
/// approval is decided and the invocation is released.
///
/// Usage:
///   Do ##class(br.musketeers.InteropMCP.TestWorkflowFix).Run()
Class br.musketeers.InteropMCP.TestWorkflowFix Extends %RegisteredObject
{

/// Workflow role that owns the approval tasks.
Parameter RoleName = "Operators";

/// Workflow user that acts on the tasks in the inbox.
Parameter OperatorName = "_SYSTEM";

/// Readonly demo tool replayed when an approval is granted.
Parameter ToolName = "PayLookup";

/// Runs the whole test suite. Prints a report and returns $$$OK when every
/// check passed; the number of failed checks is reported in the output.
ClassMethod Run() As %Status
{
    Set failed = 0
    Do ..WriteLog("=== WORKFLOW TASK COMPLETION TEST ===")
    Do ..WriteLog("")

    Do ..WriteLog("-- prerequisites --")
    Set sc = ..EnsureRole()
    If $$$ISERR(sc) {
        Do ..WriteLog("ERROR: role setup failed: "_$System.Status.GetErrorText(sc))
        Quit sc
    }
    Set sc = ..EnsureMembership()
    If $$$ISERR(sc) {
        Do ..WriteLog("ERROR: membership setup failed: "_$System.Status.GetErrorText(sc))
        Quit sc
    }

    Do ..WriteLog("")
    Do ..WriteLog("-- portal action: approve --")
    Do ..TestPortalAction("Approve", .failed)

    Do ..WriteLog("")
    Do ..WriteLog("-- portal action: reject --")
    Do ..TestPortalAction("Reject", .failed)

    Do ..WriteLog("")
    Do ..WriteLog("-- terminal action: approve --")
    Do ..TestTerminalAction(.failed)

    Do ..WriteLog("")
    If failed = 0 {
        Do ..WriteLog("=== RESULT: ALL CHECKS PASSED ===")
    } Else {
        Do ..WriteLog("=== RESULT: "_failed_" CHECK(S) FAILED ===")
    }
    Quit $$$OK
}

/// Drives one portal action end to end and asserts the resulting state.
/// The action is executed through the workflow engine, exactly as the IRIS
/// User Portal does it.
ClassMethod TestPortalAction(pAction As %String, Output pFailed As %Integer) As %Status
{
    Set apId = ""
    Set invId = ""
    Set sc = ..CreateHeldInvocation(.apId, .invId)
    If $$$ISERR(sc) {
        Do ..Check("held invocation created", 0, .pFailed)
        Do ..WriteLog("ERROR: "_$System.Status.GetErrorText(sc))
        Quit sc
    }
    Do ..Check("held invocation created", 1, .pFailed)

    Set decision = ""
    Set approver = ""
    Set taskId = ""
    Set sc = ..GetApproval(apId, .decision, .approver, .taskId)
    Do ..Check("approval row readable", $$$ISOK(sc), .pFailed)
    Do ..Check("task id stored on the approval", taskId '= "", .pFailed)

    // The task the portal opens must be the task the approval points at
    Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(taskId)
    Do ..Check("task opens polymorphically", $IsObject(task), .pFailed)
    Do ..Check("task uses WorkflowTaskResponse", $IsObject(task) && task.%IsA("br.musketeers.InteropMCP.WorkflowTaskResponse"), .pFailed)

    // Exactly one task response per request: the old code created two and
    // stored the orphan one on the approval.
    Set requestId = ""
    If $IsObject(task) {
        &sql(SELECT TaskStatus_Request INTO :requestId FROM EnsLib_Workflow.TaskResponse WHERE ID = :taskId)
    }
    Set taskCount = 0
    &sql(SELECT COUNT(*) INTO :taskCount FROM EnsLib_Workflow.TaskResponse WHERE TaskStatus_Request = :requestId)
    Do ..Check("exactly one task response per request (got "_taskCount_")", taskCount = 1, .pFailed)

    // The inbox must point at the very same task
    Set itemId = ..GetWorklistItemId(taskId, ..#OperatorName)
    Do ..Check("task listed in the operator worklist", itemId '= "", .pFailed)

    // Act exactly as the portal does
    Set msg = ""
    Set sc = ..ActAsPortal(itemId, ..#OperatorName, pAction, .msg)
    Do ..Check("portal action succeeded without ErrProductionMismatchInDeferredResponse", $$$ISOK(sc), .pFailed)
    If $$$ISERR(sc) Do ..WriteLog("portal error: "_$System.Status.GetErrorText(sc))

    // Task closed
    Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(taskId)
    If $IsObject(task) {
        Do ..Check("task marked complete", task.%TaskStatus.IsComplete = 1, .pFailed)
        Do ..Check("task action recorded (got "_task.%Action_")", task.%Action = pAction, .pFailed)
    } Else {
        Do ..Check("task marked complete", 0, .pFailed)
    }

    // Inbox cleaned
    Set itemId = ..GetWorklistItemId(taskId, ..#OperatorName)
    Do ..Check("task removed from the worklist", itemId = "", .pFailed)

    // Decision recorded
    Set sc = ..GetApproval(apId, .decision, .approver, .taskId)
    If $ZConvert(pAction, "L") = "approve" {
        Do ..Check("approval approved (got "_decision_")", decision = "approved", .pFailed)
        Do ..Check("approver recorded (got "_approver_")", approver '= "", .pFailed)
    } Else {
        Do ..Check("approval rejected (got "_decision_")", decision = "rejected", .pFailed)
        Do ..Check("rejection reason recorded", ..GetApprovalReason(apId) '= "", .pFailed)
    }

    // Invocation released (or blocked for a rejection)
    Set invStatus = ""
    Set sc = ..GetInvocationStatus(invId, .invStatus)
    If $ZConvert(pAction, "L") = "approve" {
        Do ..Check("invocation completed (got "_invStatus_")", invStatus = "completed", .pFailed)
    } Else {
        Do ..Check("invocation rejected (got "_invStatus_")", invStatus = "rejected", .pFailed)
    }
    Quit $$$OK
}

/// Drives the terminal path (WorkflowBridge.CompleteTask) and asserts the
/// approval is decided through the very same code path as the portal.
ClassMethod TestTerminalAction(Output pFailed As %Integer) As %Status
{
    Set apId = ""
    Set invId = ""
    Set sc = ..CreateHeldInvocation(.apId, .invId)
    If $$$ISERR(sc) {
        Do ..Check("held invocation created", 0, .pFailed)
        Quit sc
    }
    Do ..Check("held invocation created", 1, .pFailed)

    Set decision = ""
    Set approver = ""
    Set taskId = ""
    Set sc = ..GetApproval(apId, .decision, .approver, .taskId)
    Do ..Check("task id stored on the approval", taskId '= "", .pFailed)

    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CompleteTask(taskId, "Approve", "terminal-operator", "")
    Do ..Check("terminal completion succeeded", $$$ISOK(sc), .pFailed)
    If $$$ISERR(sc) Do ..WriteLog("terminal error: "_$System.Status.GetErrorText(sc))

    Set sc = ..GetApproval(apId, .decision, .approver, .taskId)
    Do ..Check("approval approved (got "_decision_")", decision = "approved", .pFailed)
    Do ..Check("approver recorded (got "_approver_")", approver = "terminal-operator", .pFailed)

    Set invStatus = ""
    Set sc = ..GetInvocationStatus(invId, .invStatus)
    Do ..Check("invocation completed (got "_invStatus_")", invStatus = "completed", .pFailed)
    Quit $$$OK
}

/// Creates a held invocation through the real MCP entry point, so the whole
/// approval chain is exercised.
ClassMethod CreateHeldInvocation(Output pApprovalId As %String, Output pInvocationId As %String) As %Status
{
    Set pApprovalId = ""
    Set pInvocationId = ""
    Set params = ##class(%DynamicObject).%New()
    Do params.%Set("OrderId", "WFIX-"_$Random(1000000))
    Set result = ##class(br.musketeers.InteropMCP.MetaTools).CreateWorkflowTask(..#ToolName, params.%ToJSON(), "workflow completion test")
    If '$IsObject(result) {
        Quit $$$ERROR($$$GeneralError, "CreateWorkflowTask returned no result")
    }
    Set tStatus = result.%Get("_status")
    If tStatus '= "held" {
        Quit $$$ERROR($$$GeneralError, "CreateWorkflowTask did not hold the call: "_tStatus)
    }
    Set pApprovalId = result.%Get("approvalId")
    Set pInvocationId = result.%Get("invocationId")
    If pApprovalId = "" {
        Quit $$$ERROR($$$GeneralError, "CreateWorkflowTask returned no approval id")
    }
    Quit $$$OK
}

/// Takes ownership of the worklist item and processes the action, the same
/// way the IRIS User Portal does it.
ClassMethod ActAsPortal(pItemId As %String, pUser As %String, pAction As %String, Output pMsg As %String) As %Status
{
    Set pMsg = ""
    If pItemId = "" {
        Quit $$$ERROR($$$GeneralError, "No worklist item to act on")
    }
    Set sc = ##class(EnsLib.Workflow.Engine).%TakeOwnershipForTask(pItemId, pUser, .pMsg)
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(EnsLib.Workflow.Engine).%ProcessAction(pAction, pItemId, pUser, .pMsg)
    Quit sc
}

/// Returns the id of the worklist item of pTaskId for pUser, or the empty
/// string when the task is not listed for that user.
ClassMethod GetWorklistItemId(pTaskId As %String, pUser As %String) As %String
{
    Set itemId = ""
    &sql(SELECT %ID INTO :itemId FROM EnsLib_Workflow.Worklist WHERE Task = :pTaskId AND UserName = :pUser)
    If SQLCODE = 0 Quit itemId
    Quit ""
}

/// Reads the approval row.
ClassMethod GetApproval(pApprovalId As %String, Output pDecision As %String, Output pApprover As %String, Output pTaskId As %String) As %Status
{
    Set pDecision = ""
    Set pApprover = ""
    Set pTaskId = ""
    &sql(SELECT Decision, Approver, TaskId INTO :pDecision, :pApprover, :pTaskId FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = :pApprovalId)
    If SQLCODE = 0 Quit $$$OK
    Quit $$$ERROR($$$GeneralError, "Approval not found: "_pApprovalId)
}

/// Reads the rejection reason of an approval.
ClassMethod GetApprovalReason(pApprovalId As %String) As %String
{
    Set reason = ""
    &sql(SELECT Reason INTO :reason FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = :pApprovalId)
    If SQLCODE = 0 Quit reason
    Quit ""
}

/// Reads the lifecycle status of an invocation.
ClassMethod GetInvocationStatus(pInvocationId As %String, Output pStatus As %String) As %Status
{
    Set pStatus = ""
    &sql(SELECT Status INTO :pStatus FROM br_musketeers_InteropMCP.Invocations WHERE InvocationId = :pInvocationId)
    If SQLCODE = 0 Quit $$$OK
    Quit $$$ERROR($$$GeneralError, "Invocation not found: "_pInvocationId)
}

/// Creates the workflow role when it is missing.
ClassMethod EnsureRole() As %Status
{
    Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(..#RoleName)
    If $IsObject(role) Quit $$$OK
    Set role = ##class(EnsLib.Workflow.RoleDefinition).%New()
    Set role.Name = ..#RoleName
    Set role.Description = "Interop MCP Workflow Operators"
    Set role.Capacity = 10
    Quit role.%Save()
}

/// Makes sure the acting user exists and belongs to the workflow role.
ClassMethod EnsureMembership() As %Status
{
    Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(..#RoleName)
    If '$IsObject(role) {
        Quit $$$ERROR($$$GeneralError, "Workflow role not found: "_..#RoleName)
    }
    Set user = ##class(EnsLib.Workflow.UserDefinition).%OpenId(..#OperatorName)
    If '$IsObject(user) {
        Set user = ##class(EnsLib.Workflow.UserDefinition).%New()
        Set user.Name = ..#OperatorName
        Set user.FullName = "System User"
        Set user.IsActive = 1
        Set sc = user.%Save()
        If $$$ISERR(sc) Quit sc
    }
    If $Data(^EnsLib.W.RoleMembershipD(..#RoleName, ..#OperatorName)) Quit $$$OK
    Set member = ##class(EnsLib.Workflow.RoleMembership).%New()
    Set member.Role = role
    Set member.User = user
    Set member.Title = "Operator"
    Set member.Ranking = 1
    Quit member.%Save()
}

/// Records one check result and writes it to the report.
ClassMethod Check(pLabel As %String, pOk As %Boolean, Output pFailed As %Integer) As %Status
{
    If pOk {
        Do ..WriteLog("  [ OK ] "_pLabel)
    } Else {
        Set pFailed = pFailed + 1
        Do ..WriteLog("  [FAIL] "_pLabel)
    }
    Quit $$$OK
}

/// Writes a message to the terminal.
ClassMethod WriteLog(pMessage As %String) As %Status
{
    Write pMessage, !
    Quit $$$OK
}

}
