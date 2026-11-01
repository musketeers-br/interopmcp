/// IRIS MCP Gateway - status polling tool.
/// Exposes GetInvocationStatus as a fixed agent-facing tool so agents can
/// poll the outcome of async or held invocations by their InvocationId
/// reference (returned by long-running tools and by critical tools held for
/// approval). The answer is read with dynamic SQL against the invocation
/// store and carries the same envelope the AI HUB query tools produce
/// (columns, rows, row_count, truncated, elapsed_ms); an unknown
/// InvocationId yields an empty result set.
///
/// The query is prepared as a plain SQL statement instead of a class query:
/// preparing a class query re-prepares the SQL in the caller's own context
/// and needs the class query privileges on top of the table privileges,
/// which the gateway role intentionally does not carry.
Class br.musketeers.InteropMCP.InvocationStatusTools Extends %AI.Tool
{

/// Returns the current lifecycle row(s) for one invocation: InvocationId,
/// Status, Result and the attributed caller identity as stored by
/// br.musketeers.InteropMCP.Invocations.
ClassMethod GetInvocationStatus(invocationId As %String) As %DynamicObject
{
    Set started = $ZH
    Set columns = ##class(%DynamicArray).%New()
    Set names = "InvocationId^Status^Result^AgentIdentity"
    For i = 1:1:$Length(names, "^") {
        Set col = ##class(%DynamicObject).%New()
        Do col.%Set("name", $Piece(names, "^", i))
        Do col.%Set("type", "string")
        Do columns.%Push(col)
    }
    Set rows = ##class(%DynamicArray).%New()
    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare("SELECT InvocationId, Status, Result, AgentIdentity FROM br_musketeers_InteropMCP.Invocations WHERE InvocationId = ?")
    If $$$ISOK(sc) {
        Set rs = stmt.%Execute(invocationId)
        While rs.%Next() {
            Set row = ##class(%DynamicObject).%New()
            Do row.%Set("InvocationId", rs.%Get("InvocationId"))
            Do row.%Set("Status", rs.%Get("Status"))
            Do row.%Set("Result", rs.%Get("Result"))
            Do row.%Set("AgentIdentity", rs.%Get("AgentIdentity"))
            Do rows.%Push(row)
        }
    }
    Set result = ##class(%DynamicObject).%New()
    Do result.%Set("columns", columns)
    Do result.%Set("rows", rows)
    Do result.%Set("row_count", rows.%Size())
    Do result.%Set("truncated", 0)
    Do result.%Set("elapsed_ms", ($ZH - started) * 100)
    // Friendly summary for agents
    Set msg = ""
    If rows.%Size() > 0 {
        Set r = rows.%Get(0)
        Set msg = "Invocation "_r.%Get("InvocationId")_" – Status: "_r.%Get("Status")_" | Agent: "_r.%Get("AgentIdentity")
        If r.%Get("Status") = "completed" {
            Set res = r.%Get("Result")
            If res '= "" Set msg = msg_" | Result: "_res
        } ElseIf r.%Get("Status") = "pending-approval" {
            Set msg = msg_" | Awaiting human approval"
        } ElseIf r.%Get("Status") = "rejected" {
            Set msg = msg_" | Rejected"
        }
    } Else {
        Set msg = "No invocation found for ID "_invocationId
    }
    Do result.%Set("text", msg)
    Quit result
}

}
