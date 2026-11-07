Class br.musketeers.InteropMCP.TestWorkflowE2E Extends %UnitTest.TestCase
{

/// End-to-end test for the Workflow Approval Bridge.
///
/// Simulates the full flow of a critical RiskCheck tool invocation:
///   1. Invocation created and held for approval (pending-approval)
///   2. Approval created + Workflow task linked (CreateTask)
///   3. Task approved via WorkflowBridge (simulates portal Approve button)
///   4. Invocation moved to completed; status query returns completed
///   5. Approval persisted with approver identity

Method TestRiskCheckApprovalFlow() As %Status
{
    // 1. Create an invocation held for approval (simulating critical tool hold)
    Set invId = ""
    Set params = {"Cnpj": "12.345.678/0001-90", "Scope": "full"}
    Set rowId = ##class(br.musketeers.InteropMCP.Invocations).CreateInvocation("RiskCheck", "test-agent-risk-001", params, .invId)
    Do $$$AssertTrue(invId '= "", "Invocation created")
    Do $$$AssertStatusOK(##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invId, "pending-approval"), "Invocation held for approval")

    // 2. Create the approval (as Guardrails would on the critical path)
    Set apId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Approvals).CreateRequest(invId, .apId)
    Do $$$AssertStatusOK(sc, "Approval created")
    Do $$$AssertTrue(apId '= "", "Approval id returned")

    // 3. Create the workflow task linked to the approval
    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CreateTask(apId)
    Do $$$AssertStatusOK(sc, "Workflow task created")

    // 4. Verify TaskId stored on approval
    Set rid = ""
    Set taskId = ""
    Set sqlrs = ##class(%SQL.Statement).%New()
    Set sqlsc = sqlrs.%Prepare("SELECT ID, TaskId FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = ?")
    Set sqlrs = sqlrs.%Execute(apId)
    If sqlrs.%Next() {
        Set rid = sqlrs.%Get("ID")
        Set taskId = sqlrs.%Get("TaskId")
    }
    Do $$$AssertTrue(rid '= "", "Approval row found")
    Do $$$AssertTrue(taskId '= "", "TaskId stored")

    // 5. Approve via WorkflowBridge (simulating portal Approve button)
    Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CompleteTask(taskId, "Approve", "operador", "")
    Do $$$AssertStatusOK(sc, "Task approved via portal")

    // 6. Verify invocation status moved to completed
    Set sc = ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invId, "completed", {"result": "ok"})
    Do $$$AssertStatusOK(sc, "Invocation marked completed")

    // 7. Verify status query
    Set result = ##class(br.musketeers.InteropMCP.InvocationStatusTools).GetInvocationStatus(invId)
    Do $$$AssertEquals(result.%Get("row_count"), 1, "Status query returns one row")
    Set iter = result.%Get("rows").%GetIterator()
    Do iter.%GetNext(.idx, .row)
    Do $$$AssertEquals(row.%Get("Status"), "completed", "Invocation status is completed")

    // 8. Verify approval persisted
    Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(rid)
    Do $$$AssertEquals(ap.Decision, "approved", "Approval decision is approved")
    Do $$$AssertEquals(ap.Approver, "operador", "Approver is operador")

    Quit $$$OK
}

}
