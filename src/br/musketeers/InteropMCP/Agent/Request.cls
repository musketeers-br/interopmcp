/// IRIS MCP Gateway - the agent's request.
/// Carries the goal a caller submits to the agent in plain language. The
/// published input schema of the agent tool is derived from this class by the
/// gateway's existing schema mapper, so the agent is published with the same
/// one-argument shape as any other tool.
Class br.musketeers.InteropMCP.Agent.Request Extends Ens.Request
{

/// What the caller wants, in plain language. Required: an agent with no goal
/// has nothing to do. The goal is long because the REST endpoint hands the
/// agent the goal together with the text of an attached document.
Property Goal As %String(MAXLEN = 64000) [ Required ];

/// The invocation the run belongs to. The gateway fills it when it dispatches
/// the run, so that a business host performing the run in the background can
/// record the outcome against the invocation the caller is polling. It is the
/// gateway's own channel and is not published to the caller.
Property GatewayInvocationId As %String;

Storage Default
{
<Data name="RequestDefaultData">
<Subscript>"Request"</Subscript>
<Value name="1">
<Value>Goal</Value>
</Value>
<Value name="2">
<Value>GatewayInvocationId</Value>
</Value>
</Data>
<DefaultData>RequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
