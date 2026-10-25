/// IRIS MCP Gateway - invocation audit store (the gateway-side audit
/// backbone). One row per agent-initiated tool call, covering the full
/// lifecycle: parameters, caller identity, status transitions, result and
/// timing. Every tool call - successful or not - produces exactly one row,
/// which is what makes 100 percent of AI-triggered executions auditable.
/// Status machine (transitions in words):
/// - received, then executing, then completed or failed
/// - received, then pending-approval, then executing or rejected (critical path;
///   rejected rows never execute)
/// Rows are opened by row ID; InvocationId (a GUID with a unique index) is
/// resolved through embedded SQL - see UpdateStatus.
Class br.musketeers.InteropMCP.Invocations Extends %Persistent
{

/// Public identifier returned to the agent as the processing reference for
/// async or held calls. GUID generated at creation; unique index enforced.
Property InvocationId As %String(MAXLEN = 64);

/// Name of the invoked tool as published in the catalog.
Property ToolName As %String(MAXLEN = 100);

/// Caller identity: authenticated agent identity on provisioned endpoints,
/// or an explicit local-dev marker when the endpoint runs unauthenticated.
Property AgentIdentity As %String(MAXLEN = 200);

/// Call arguments as JSON, stored only after schema validation. Kept as a
/// string so the exact agent-supplied payload is preserved for audit.
Property Parameters As %String(MAXLEN = 10000);

/// Lifecycle state; values and transitions documented at class level.
/// Invalid transitions (for example from rejected straight to executing) are refused by callers.
Property Status As %String(MAXLEN = 32);

/// Business result as JSON, populated when the invocation reaches a terminal
/// successful state.
Property Result As %String(MAXLEN = 10000);

/// Error detail when the invocation failed or was refused.
Property ErrorMessage As %String(MAXLEN = 2000);

/// Reserved for native interoperability header linkage. The gateway never
/// writes into production structures, so this stays 0 in the current design;
/// the native trace is produced by the production components themselves.
Property MessageHeaderId As %Integer;

/// Timestamp when the invocation was recorded (creation time).
Property StartedAt As %TimeStamp;

/// Timestamp of the last lifecycle update; StartedAt/EndedAt give the
/// duration reported in audit queries.
Property EndedAt As %TimeStamp;

Index InvocationIdIdx On InvocationId [ Unique ];

Index StatusIdx On Status;

/// Records a new invocation in state received and returns its InvocationId
/// through pId. Parameters must already be validated by the caller (the
/// generated tool methods validate against the tool schema before invoking).
ClassMethod CreateInvocation(pTool As %String, pAgent As %String, pParams As %DynamicObject, Output pId As %String) As %Status
{
    Set inv = ..%New()
    Set pId = $SYSTEM.Util.CreateGUID()
    Set inv.InvocationId = pId
    Set inv.ToolName = pTool
    Set inv.AgentIdentity = pAgent
    Set inv.Parameters = pParams.%ToJSON()
    Set inv.Status = "received"
    Set inv.StartedAt = $ZDateTime($Horolog, 3)
    Quit inv.%Save()
}

/// Applies a lifecycle transition to the invocation identified by pId
/// (the InvocationId GUID). Persists the optional result payload, error
/// message and native header id. Fails when pId is empty or unknown.
ClassMethod UpdateStatus(pId As %String, pStatus As %String, pResult As %DynamicObject = "", pError As %String = "", pHeaderId As %Integer = 0) As %Status
{
    If pId = "" Quit $$$ERROR($$$GeneralError, "InvocationId required")
    Set rid = ""
    &sql(SELECT ID INTO :rid FROM br.musketeers.InteropMCP.Invocations WHERE InvocationId = :pId)
    If rid = "" Quit $$$ERROR($$$GeneralError, "Invocation not found: "_pId)
    Set inv = ..%OpenId(rid)
    Set inv.Status = pStatus
    Set inv.EndedAt = $ZDateTime($Horolog, 3)
    If $IsObject(pResult) Set inv.Result = pResult.%ToJSON()
    If pError '= "" Set inv.ErrorMessage = pError
    If pHeaderId Set inv.MessageHeaderId = pHeaderId
    Quit inv.%Save()
}

Storage Default
{
<Data name="InvocationsDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>InvocationId</Value>
</Value>
<Value name="3">
<Value>ToolName</Value>
</Value>
<Value name="4">
<Value>AgentIdentity</Value>
</Value>
<Value name="5">
<Value>Parameters</Value>
</Value>
<Value name="6">
<Value>Status</Value>
</Value>
<Value name="7">
<Value>Result</Value>
</Value>
<Value name="8">
<Value>ErrorMessage</Value>
</Value>
<Value name="9">
<Value>MessageHeaderId</Value>
</Value>
<Value name="10">
<Value>StartedAt</Value>
</Value>
<Value name="11">
<Value>EndedAt</Value>
</Value>
</Data>
<DataLocation>^InteropMCP.InvocationsD</DataLocation>
<DefaultData>InvocationsDefaultData</DefaultData>
<IdLocation>^InteropMCP.InvocationsD</IdLocation>
<IndexLocation>^InteropMCP.InvocationsI</IndexLocation>
<StreamLocation>^InteropMCP.InvocationsS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
