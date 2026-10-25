/// IRIS MCP Gateway - human-in-the-loop approval store for critical tools.
/// When a critical tool is invoked, Guardrails creates one ApprovalRequest
/// linked to the held ToolInvocation. The invocation stays in
/// pending-approval and NEVER reaches the Business Service until an operator
/// approves it through this class; a rejected or cancelled request marks the
/// invocation as rejected and it never executes.
/// Lifecycle: pending becomes approved or rejected. There is no automatic expiry:
/// pending items remain until decided or explicitly cancelled.
/// Rows are opened by row ID; ApprovalId (a GUID with a unique index) is
/// resolved to the row through embedded SQL - see Approve and Reject.
Class br.musketeers.InteropMCP.Approvals Extends %Persistent
{

/// Public identifier returned to the caller and used by operators to make
/// the decision. GUID generated at creation; unique index enforced.
Property ApprovalId As %String(MAXLEN = 64);

/// ToolInvocation.InvocationId this approval gates. Set at creation while
/// the invocation is parked in pending-approval.
Property InvocationId As %String(MAXLEN = 64);

/// Decision state: pending, approved or rejected. Only approved releases
/// the invocation for execution; rejected never executes.
Property Decision As %String(MAXLEN = 16);

/// Operator identity that made the decision. Required when Decision is
/// approved or rejected.
Property Approver As %String(MAXLEN = 200);

/// Timestamp of the decision. Required when Decision is approved or
/// rejected.
Property DecidedAt As %TimeStamp;

/// Free-text justification. Mandatory for rejections, optional for
/// cancellations (which are recorded as rejections with a reason).
Property Reason As %String(MAXLEN = 2000);

/// Creates a pending approval request gating pInvocationId and returns the
/// new ApprovalId through pApprovalId. Called by Guardrails on the critical
/// path, right after the invocation is recorded as pending-approval.
ClassMethod CreateRequest(pInvocationId As %String, Output pApprovalId As %String) As %Status
{
    Set ap = ..%New()
    Set pApprovalId = $SYSTEM.Util.CreateGUID()
    Set ap.ApprovalId = pApprovalId
    Set ap.InvocationId = pInvocationId
    Set ap.Decision = "pending"
    Quit ap.%Save()
}

/// Records an approval by pApprover and releases the gated invocation to the
/// execution path (the release itself reuses the original call parameters
/// through the invoker). Fails when the ApprovalId is unknown.
ClassMethod Approve(pApprovalId As %String, pApprover As %String) As %Status
{
    Set rid = ""
    &sql(SELECT ID INTO :rid FROM br.musketeers.InteropMCP.Approvals WHERE ApprovalId = :pApprovalId)
    If rid = "" Quit $$$ERROR($$$GeneralError, "Approval not found: "_pApprovalId)
    Set ap = ..%OpenId(rid)
    Set ap.Decision = "approved"
    Set ap.Approver = pApprover
    Set ap.DecidedAt = $ZDateTime($Horolog, 3)
    Set logData = ##class(%DynamicObject).%New()
    Do logData.%Set("approval", pApprovalId)
    Do logData.%Set("approver", pApprover)
    Do ##class(br.musketeers.InteropMCP.Log).Write("info", "approval", "Approved", logData)
    Quit ap.%Save()
}

/// Records a rejection with a mandatory reason. The gated invocation is
/// marked rejected and never executes; the calling agent can observe the
/// outcome through the status tool. Fails when the ApprovalId is unknown.
ClassMethod Reject(pApprovalId As %String, pApprover As %String, pReason As %String) As %Status
{
    Set rid = ""
    &sql(SELECT ID INTO :rid FROM br.musketeers.InteropMCP.Approvals WHERE ApprovalId = :pApprovalId)
    If rid = "" Quit $$$ERROR($$$GeneralError, "Approval not found: "_pApprovalId)
    Set ap = ..%OpenId(rid)
    Set ap.Decision = "rejected"
    Set ap.Approver = pApprover
    Set ap.DecidedAt = $ZDateTime($Horolog, 3)
    Set ap.Reason = pReason
    Set logData = ##class(%DynamicObject).%New()
    Do logData.%Set("approval", pApprovalId)
    Do logData.%Set("approver", pApprover)
    Do logData.%Set("reason", pReason)
    Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "approval", "Rejected", logData)
    Quit ap.%Save()
}

/// Operator cancellation of a stale pending item. Implemented as a rejection
/// carrying the cancellation reason; as with any rejection, the gated
/// invocation never executes.
ClassMethod Cancel(pApprovalId As %String, pOperator As %String, pReason As %String) As %Status
{
    Quit ..Reject(pApprovalId, pOperator, pReason)
}

/// Lists every request still in pending state (their ApprovalIds) by walking
/// the storage global directly. Used by operators and by the health snapshot
/// to surface undecided critical calls.
ClassMethod ListPending(Output pList As %DynamicObject) As %Status
{
    Set pending = ##class(%DynamicArray).%New()
    Set id = ""
    For {
        Set id = $Order(^InteropMCP.ApprovalsD(id))
        If id = "" Quit
        Set ap = ..%OpenId(id)
        If $IsObject(ap) {
            If ap.Decision = "pending" Do pending.%Push(ap.ApprovalId)
        }
    }
    Set pList = ##class(%DynamicObject).%New()
    Do pList.%Set("pending", pending)
    Quit $$$OK
}

Storage Default
{
<Data name="ApprovalsDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>ApprovalId</Value>
</Value>
<Value name="3">
<Value>InvocationId</Value>
</Value>
<Value name="4">
<Value>Decision</Value>
</Value>
<Value name="5">
<Value>Approver</Value>
</Value>
<Value name="6">
<Value>DecidedAt</Value>
</Value>
<Value name="7">
<Value>Reason</Value>
</Value>
</Data>
<DataLocation>^InteropMCP.ApprovalsD</DataLocation>
<DefaultData>ApprovalsDefaultData</DefaultData>
<IdLocation>^InteropMCP.ApprovalsD</IdLocation>
<IndexLocation>^InteropMCP.ApprovalsI</IndexLocation>
<StreamLocation>^InteropMCP.ApprovalsS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
