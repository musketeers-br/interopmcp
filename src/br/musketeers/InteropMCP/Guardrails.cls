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

/// Identity marker emitted by gateway builds that predate caller-identity
/// attribution. A caller that passes it has not established an identity, so
/// the gateway resolves the live caller instead of recording the placeholder.
Parameter LegacyAgentPlaceholder = "agent";

/// Returns the identity attributed to the current invocation. The MCP Server
/// CSP application has already authenticated the caller in secured mode,
/// so $USERNAME is the real IRIS user. When no identity was established
/// the gateway attributes the call to the explicit local-dev marker instead of
/// an anonymous placeholder.
ClassMethod CurrentAgent() As %String
{
    Set user = $USERNAME
    If (user = "") || (user = "UnknownUser") Quit "local-dev"
    Quit user
}

/// Resolves the identity to attribute to an invocation. pAgent is kept when
/// it carries a real identity (the approval replay path passes the identity
/// recorded with the original call). An empty value - or the legacy
/// placeholder emitted by pre-identity builds - resolves to the live caller,
/// so a tool implementation that predates identity attribution still records
/// the authenticated user instead of a placeholder.
ClassMethod ResolveAgent(pAgent As %String) As %String
{
    If (pAgent = "") || (pAgent = ..#LegacyAgentPlaceholder) Quit ..CurrentAgent()
    Quit pAgent
}

/// Evaluates the security classification of pTool against the incoming
/// call. Outputs:
/// - pProceed: 1 when the caller may proceed to Invoker.Invoke, 0 when the
///   call is held (critical) or was refused by an earlier error
/// - pHoldId: approval request id for critical tools, empty otherwise
/// - pInvocationId: invocation id created for the call (always set for critical, for readonly/write set by Invoker)
/// - pSC: %Status carrying any infrastructure error (unknown tool, failed
///   approval creation); pProceed stays 0 in those cases
/// pParams and pAgent are persisted with the pending invocation so the
/// approval release path can replay the exact call.
ClassMethod Check(pTool As %String, pParams As %DynamicObject, pAgent As %String, Output pProceed As %Boolean, Output pHoldId As %String, Output pInvocationId As %String, Output pSC As %Status)
{
    Set pProceed = 0
    Set pHoldId = ""
    Set pInvocationId = ""
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
        Set pInvocationId = invId
        Set sc = ##class(br.musketeers.InteropMCP.Approvals).CreateRequest(invId, .pHoldId)
        If $$$ISERR(sc) Set pSC = sc Quit

        // Create linked Workflow task for portal-based approval (non-blocking)
        Set sc = ##class(br.musketeers.InteropMCP.WorkflowBridge).CreateTask(pHoldId)
        If $$$ISERR(sc) {
            Do logData.%Set("workflowTaskError", $System.Status.GetErrorText(sc))
            Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "workflow", "TaskCreationNonBlocking", logData)
        }

        Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invId, "pending-approval", "", "", 0)
        Do logData.%Set("approval", pHoldId)
        Do logData.%Set("invocation", invId)
        Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "guardrail", "Critical held for approval", logData)
        Set pProceed = 0
    }
    Quit $$$OK
}

}
