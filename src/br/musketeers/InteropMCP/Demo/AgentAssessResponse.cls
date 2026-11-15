/// IRIS MCP Gateway - the demonstration's REST response for the agent.
/// Carries what the agent did and what it answered, in the same shape the
/// agent's own response carries, so that a caller of the REST endpoint and a
/// caller of the MCP tool see the same facts about the same run.
Class br.musketeers.InteropMCP.Demo.AgentAssessResponse Extends Ens.Response
{

/// The outcome of the run: completed or failed.
Property Status As %String;

/// The invocation the run was recorded under. The run is in the gateway's
/// invocation store, like every other invocation, and this id identifies it.
Property InvocationId As %String;

/// The agent's final answer. Long: the answer is a model's prose.
Property Answer As %String(MAXLEN = 32000);

/// The published capabilities the agent invoked.
/// Stored as JSON text (%String) so the Message Viewer / Visual Trace can
/// render it - %DynamicArray is not a %XML.Adaptor and breaks XML display.
Property CapabilitiesUsed As %String(MAXLEN = 32000);

/// The passages the agent retrieved, each with the source document it came
/// from and the score it matched with.
/// Stored as JSON text (%String) for the same reason as CapabilitiesUsed.
Property Retrievals As %String(MAXLEN = 32000);

Storage Default
{
<Data name="AgentAssessResponseDefaultData">
<Subscript>"AgentAssessResponse"</Subscript>
<Value name="1">
<Value>Status</Value>
</Value>
<Value name="2">
<Value>InvocationId</Value>
</Value>
<Value name="3">
<Value>Answer</Value>
</Value>
<Value name="4">
<Value>CapabilitiesUsed</Value>
</Value>
<Value name="5">
<Value>Retrievals</Value>
</Value>
</Data>
<DefaultData>AgentAssessResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
