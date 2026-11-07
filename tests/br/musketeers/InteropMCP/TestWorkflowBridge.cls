Class br.musketeers.InteropMCP.TestWorkflowBridge Extends %UnitTest.TestCase
{

/// Unit tests for br.musketeers.InteropMCP.WorkflowBridge.
/// Covers task creation (TaskId storage, actions buttons), task completion
/// (Approve/Reject propagation to Approvals), idempotency and invalid decisions.

/// Setup: ensure the Operadores workflow role exists for task distribution.
Method OnBeforeEachTest() As %Status
{
    Set sc = ##class(EnsLib.Workflow.RoleDefinition).CreateRole("Operadores")
    Quit $$$OK
}

/// Unit: CreateTask stores TaskId on Approval and sets Actions="Approve,Reject" (portal buttons).
Method TestCreateTask() As %Status
{
    Set invId = "TEST-WF-INV-"_$ZDateTime($Horolog,3)
    Set apId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Approvals).CreateRequest(invId, .apId)
    Do $$$AssertStatusOK(sc, "Approval created")
    Do $$$AssertTrue(apId '= "", "Approval id returned")

    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CreateTask(apId)
    Do $$$AssertStatusOK(sc, "CreateTask succeeded")

    // Look up internal row id by ApprovalId
    Set rid = ""
    Set sqlrs = ##class(%SQL.Statement).%New()
    Set sqlsc = sqlrs.%Prepare("SELECT ID FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = ?")
    Set sqlrs = sqlrs.%Execute(apId)
    If sqlrs.%Next() { Set rid = sqlrs.%Get("ID") }
    Do $$$AssertTrue(rid '= "", "Approval row found")

    Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(rid)
    Do $$$AssertTrue(ap.TaskId '= "", "TaskId stored on Approval")
    Do $$$AssertEquals(ap.Decision, "pending", "Decision still pending after task creation")

    // Verify TaskResponse actions (buttons Approve/Reject)
    Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(ap.TaskId)
    Do $$$AssertTrue($IsObject(task), "TaskResponse opened")
    Do $$$AssertEquals(task.%TaskStatus.Request.%Actions, "Approve,Reject", "Task actions include Approve/Reject")

    Quit $$$OK
}

/// Unit: CompleteTask("Approve") marks task complete and approves the Approval.
Method TestCompleteTaskApprove() As %Status
{
    Set invId = "TEST-WF-INV2-"_$ZDateTime($Horolog,3)
    Set apId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Approvals).CreateRequest(invId, .apId)
    Do $$$AssertStatusOK(sc, "Approval created")

    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CreateTask(apId)
    Do $$$AssertStatusOK(sc, "CreateTask succeeded")

    // Find task id
    Set rid = ""
    Set taskId = ""
    Set sqlrs = ##class(%SQL.Statement).%New()
    Set sqlsc = sqlrs.%Prepare("SELECT ID, TaskId FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = ?")
    Set sqlrs = sqlrs.%Execute(apId)
    If sqlrs.%Next() {
        Set rid = sqlrs.%Get("ID")
        Set taskId = sqlrs.%Get("TaskId")
    }
    Do $$$AssertTrue(taskId '= "", "TaskId found")

    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CompleteTask(taskId, "Approve", "operador", "")
    Do $$$AssertStatusOK(sc, "CompleteTask Approve succeeded")

    // Approval should now be approved
    Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(rid)
    Do $$$AssertEquals(ap.Decision, "approved", "Decision moved to approved")
    Do $$$AssertEquals(ap.Approver, "operador", "Approver recorded")
    Do $$$AssertTrue(ap.DecidedAt '= "", "DecidedAt recorded")

    // TaskResponse should be complete
    Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(taskId)
    Do $$$AssertEquals(task.%TaskStatus.IsComplete, 1, "Task marked complete")
    Do $$$AssertEquals(task.%Action, "Approve", "Task action recorded")

    Quit $$$OK
}

/// Unit: CompleteTask("Reject") marks task complete and rejects the Approval.
Method TestCompleteTaskReject() As %Status
{
    Set invId = "TEST-WF-INV3-"_$ZDateTime($Horolog,3)
    Set apId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Approvals).CreateRequest(invId, .apId)
    Do $$$AssertStatusOK(sc, "Approval created")

    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CreateTask(apId)
    Do $$$AssertStatusOK(sc, "CreateTask succeeded")

    Set rid = ""
    Set taskId = ""
    Set sqlrs = ##class(%SQL.Statement).%New()
    Set sqlsc = sqlrs.%Prepare("SELECT ID, TaskId FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = ?")
    Set sqlrs = sqlrs.%Execute(apId)
    If sqlrs.%Next() {
        Set rid = sqlrs.%Get("ID")
        Set taskId = sqlrs.%Get("TaskId")
    }

    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CompleteTask(taskId, "Reject", "operador", "Scope not permitted")
    Do $$$AssertStatusOK(sc, "CompleteTask Reject succeeded")

    Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(rid)
    Do $$$AssertEquals(ap.Decision, "rejected", "Decision moved to rejected")
    Do $$$AssertEquals(ap.Reason, "Scope not permitted", "Reason recorded")
    Do $$$AssertEquals(ap.Approver, "operador", "Approver recorded")

    Quit $$$OK
}

/// Unit: CompleteTask is idempotent (second decision on same task does not replay).
Method TestCompleteTaskIdempotent() As %Status
{
    Set invId = "TEST-WF-INV4-"_$ZDateTime($Horolog,3)
    Set apId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Approvals).CreateRequest(invId, .apId)
    Do $$$AssertStatusOK(sc, "Approval created")

    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CreateTask(apId)
    Do $$$AssertStatusOK(sc, "CreateTask succeeded")

    Set rid = ""
    Set taskId = ""
    Set sqlrs = ##class(%SQL.Statement).%New()
    Set sqlsc = sqlrs.%Prepare("SELECT ID, TaskId FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = ?")
    Set sqlrs = sqlrs.%Execute(apId)
    If sqlrs.%Next() {
        Set rid = sqlrs.%Get("ID")
        Set taskId = sqlrs.%Get("TaskId")
    }

    // First decision
    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CompleteTask(taskId, "Approve", "operador", "")
    Do $$$AssertStatusOK(sc, "First CompleteTask Approve succeeded")

    // Second decision on same task -> idempotent OK
    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CompleteTask(taskId, "Reject", "operador", "")
    Do $$$AssertStatusOK(sc, "Second CompleteTask is idempotent OK")

    // Decision should remain from first call
    Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(rid)
    Do $$$AssertEquals(ap.Decision, "approved", "First decision preserved (idempotent)")
    Do $$$AssertEquals(ap.Approver, "operador", "First approver preserved")

    Quit $$$OK
}

/// Unit: CompleteTask refuses an invalid decision.
Method TestCompleteTaskInvalidDecision() As %Status
{
    Set invId = "TEST-WF-INV5-"_$ZDateTime($Horolog,3)
    Set apId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Approvals).CreateRequest(invId, .apId)
    Do $$$AssertStatusOK(sc, "Approval created")

    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CreateTask(apId)
    Do $$$AssertStatusOK(sc, "CreateTask succeeded")

    Set rid = ""
    Set taskId = ""
    Set sqlrs = ##class(%SQL.Statement).%New()
    Set sqlsc = sqlrs.%Prepare("SELECT ID, TaskId FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = ?")
    Set sqlrs = sqlrs.%Execute(apId)
    If sqlrs.%Next() {
        Set rid = sqlrs.%Get("ID")
        Set taskId = sqlrs.%Get("TaskId")
    }

    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CompleteTask(taskId, "Maybe", "operador", "")
    Do $$$AssertTrue($$$ISERR(sc), "Invalid decision refused")

    // Approval remains pending
    Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(rid)
    Do $$$AssertEquals(ap.Decision, "pending", "Decision still pending after invalid attempt")

    Quit $$$OK
}

}
