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

/// IRIS Workflow Task ID linked to this approval. Populated when a Workflow
/// task is created for operator decision via Management Portal. Empty when
/// the approval is decided solely through terminal commands.
Property TaskId As %String(MAXLEN = 64);

/// Unique index on TaskId so each Workflow task links to at most one approval.
Index TaskIdIdx On TaskId [ Unique ];

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
    &sql(SELECT ID INTO :rid FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = :pApprovalId)
    If rid = "" Quit $$$ERROR($$$GeneralError, "Approval not found: "_pApprovalId)

    // Exclusive lock to prevent concurrent decision race conditions
    Lock +^InteropMCP.ApprovalsD(rid):10
    If $Test = 0 Quit $$$ERROR($$$GeneralError, "Could not acquire lock on approval: "_pApprovalId)

    Set ap = ..%OpenId(rid)
    If ap.Decision '= "pending" {
        Lock -^InteropMCP.ApprovalsD(rid)
        Quit $$$ERROR($$$GeneralError, "Approval already decided")
    }
    Set ap.Decision = "approved"
    Set ap.Approver = pApprover
    Set ap.DecidedAt = $ZDateTime($Horolog, 3)
    Set sc = ap.%Save()
    Lock -^InteropMCP.ApprovalsD(rid)
    If $$$ISERR(sc) Quit sc
    Set logData = ##class(%DynamicObject).%New()
    Do logData.%Set("approval", pApprovalId)
    Do logData.%Set("approver", pApprover)
    Do ##class(br.musketeers.InteropMCP.Log).Write("info", "approval", "Approved", logData)
    Set invId = ap.InvocationId
    Set invRid = ##class(br.musketeers.InteropMCP.Invocations).GetRowId(invId)
    If invRid '= "" {
        Set inv = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(invRid)
        Set sc = ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invId, "executing", "", "", 0)
        If $$$ISOK(sc) {
            // Replay original call
            Set params = ##class(%DynamicObject).%FromJSON(inv.Parameters)
            Set agent = inv.AgentIdentity
            // Resolve tool name from invocation
            Set toolName = inv.ToolName
            Set scInv = ##class(br.musketeers.InteropMCP.Invoker).Invoke(toolName, params, agent, .dummyId, .resp, invId)
            If $$$ISERR(scInv) {
                Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invId, "failed", "", "Approval replay failed", 0)
            } Else {
                // Invoker already updated status to completed with serialized response
            }
        }
    }
    Quit sc
}

/// Records a rejection with a mandatory reason. The gated invocation is
/// marked rejected and never executes; the calling agent can observe the
/// outcome through the status tool. Fails when the ApprovalId is unknown.
ClassMethod Reject(pApprovalId As %String, pApprover As %String, pReason As %String) As %Status
{
    Set rid = ""
    &sql(SELECT ID INTO :rid FROM br_musketeers_InteropMCP.Approvals WHERE ApprovalId = :pApprovalId)
    If rid = "" Quit $$$ERROR($$$GeneralError, "Approval not found: "_pApprovalId)

    // Exclusive lock to prevent concurrent decision race conditions
    Lock +^InteropMCP.ApprovalsD(rid):10
    If $Test = 0 Quit $$$ERROR($$$GeneralError, "Could not acquire lock on approval: "_pApprovalId)

    Set ap = ..%OpenId(rid)
    If ap.Decision '= "pending" {
        Lock -^InteropMCP.ApprovalsD(rid)
        Quit $$$ERROR($$$GeneralError, "Approval already decided")
    }
    Set ap.Decision = "rejected"
    Set ap.Approver = pApprover
    Set ap.DecidedAt = $ZDateTime($Horolog, 3)
    Set ap.Reason = pReason
    Set sc = ap.%Save()
    Lock -^InteropMCP.ApprovalsD(rid)
    If $$$ISERR(sc) Quit sc
    Set logData = ##class(%DynamicObject).%New()
    Do logData.%Set("approval", pApprovalId)
    Do logData.%Set("approver", pApprover)
    Do logData.%Set("reason", pReason)
    Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "approval", "Rejected", logData)

    // Mark invocation as rejected
    Set invId = ap.InvocationId
    Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invId, "rejected", "", pReason, 0)
    Quit sc
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
<Value name="8">
<Value>TaskId</Value>
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
