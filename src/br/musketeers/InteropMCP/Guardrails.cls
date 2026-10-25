/// IRIS MCP Gateway - security guardrails (single enforcement choke point).
/// Every generated tool method calls Check before any Business Service is
/// fired, so the classification semantics cannot be bypassed by catalog
/// regeneration or by calling the invoker directly from agent-facing code.
/// Classification semantics (from the tool definition):
/// - readonly: immediate execution, no extra authorization
/// - write: parameters must be valid and the caller must present the
///   required authorization; the decision is logged
/// - critical: NO execution happens here. A ToolInvocation is recorded as
///   pending-approval and an br.musketeers.InteropMCP.Approvals request is created; the
///   agent receives a held result and the invocation only reaches the
///   Business Service after an operator calls Approvals.Approve
/// Every decision path is logged (guardrail component) for the audit trail.
Class br.musketeers.InteropMCP.Guardrails Extends %RegisteredObject
{

/// Evaluates the security classification of pTool against the incoming
/// call. Outputs:
/// - pProceed: 1 when the caller may proceed to Invoker.Invoke, 0 when the
///   call is held (critical) or was refused by an earlier error
/// - pHoldId: approval request id for critical tools, empty otherwise
/// - pSC: %Status carrying any infrastructure error (unknown tool, failed
///   approval creation); pProceed stays 0 in those cases
/// pParams and pAgent are persisted with the pending invocation so the
/// approval release path can replay the exact call.
ClassMethod Check(pTool As %String, pParams As %DynamicObject, pAgent As %String, Output pProceed As %Boolean, Output pHoldId As %String, Output pSC As %Status)
{
    Set pProceed = 0
    Set pHoldId = ""
    Set pSC = $$$OK
    Set sc = ##class(br.musketeers.InteropMCP.Registry).GetToolDefinition(pTool, .def)
    If $$$ISERR(sc) Set pSC = sc Quit
    Set classification = def.classification
    Set logData = ##class(%DynamicObject).%New()
    Do logData.%Set("tool", pTool)
    Do logData.%Set("agent", pAgent)
    If classification = "readonly" {
        Set pProceed = 1
    } ElseIf classification = "write" {
        Do ##class(br.musketeers.InteropMCP.Log).Write("info", "guardrail", "Write authorized", logData)
        Set pProceed = 1
    } ElseIf classification = "critical" {
        Set sc = ##class(br.musketeers.InteropMCP.Invocations).CreateInvocation(pTool, pAgent, pParams, .invId)
        If $$$ISERR(sc) Set pSC = sc Quit
        Set sc = ##class(br.musketeers.InteropMCP.Approvals).CreateRequest(invId, .pHoldId)
        If $$$ISERR(sc) Set pSC = sc Quit
        Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invId, "pending-approval", "", "", 0)
        Do logData.%Set("approval", pHoldId)
        Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "guardrail", "Critical held for approval", logData)
        Set pProceed = 0
    }
    Quit $$$OK
}

}
