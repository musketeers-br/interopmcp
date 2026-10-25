/// IRIS MCP Gateway - status polling tool.
/// Exposes GetInvocationStatus as a fixed agent-facing tool so agents can
/// poll the outcome of async or held invocations by their InvocationId
/// reference (returned by long-running tools and by critical tools held for
/// approval). Implemented as a SQL query over the invocation store; the
/// bridge serializes the result rows (columns, rows, row_count) into the
/// tool response. An unknown InvocationId yields an empty result set.
Class br.musketeers.InteropMCP.InvocationStatusTools Extends %AI.Tool
{

/// Returns the current lifecycle row(s) for one invocation: InvocationId,
/// Status and Result as stored by br.musketeers.InteropMCP.Invocations.
Query GetInvocationStatus(invocationId As %String) As %SQLQuery(
    ROWSPEC = "InvocationId:%String,Status:%String,Result:%String") [ SqlProc ]
{
    SELECT InvocationId, Status, Result FROM br.musketeers.InteropMCP.Invocations WHERE InvocationId = :invocationId
}

}
