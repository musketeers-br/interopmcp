/// IRIS MCP Gateway - the agent's response.
/// Carries what the agent did and what it answered. The caller-facing envelope
/// is the gateway's existing one - the generated tool wraps this response with
/// _status, invocationId and message - so the agent tool is indistinguishable
/// in shape from every other published tool.
Class br.musketeers.InteropMCP.Agent.Response Extends Ens.Response
{

/// The agent's final answer to the caller. The answer is a model's prose, so
/// it is long: the default %String length of 50 would reject it and the
/// run would end in a validation error instead of an answer.
Property Answer As %String(MAXLEN = 32000);

/// The published capabilities the agent invoked, each with the identifier of
/// the invocation it produced, so the run can be correlated with the audit.
/// Stored as JSON text (%String) so the Message Viewer / Visual Trace can
/// render it - %DynamicArray is not a %XML.Adaptor and breaks XML display.
Property CapabilitiesUsed As %String(MAXLEN = 32000);

/// The passages the agent retrieved, each with the source document it came
/// from and the score it matched with.
/// Stored as JSON text (%String) for the same reason as CapabilitiesUsed.
Property Retrievals As %String(MAXLEN = 32000);

/// The outcome of the run: completed, failed, held or blocked.
Property Status As %String;

Storage Default
{
<Data name="ResponseDefaultData">
<Subscript>"Response"</Subscript>
<Value name="1">
<Value>Answer</Value>
</Value>
<Value name="2">
<Value>CapabilitiesUsed</Value>
</Value>
<Value name="3">
<Value>Retrievals</Value>
</Value>
<Value name="4">
<Value>Status</Value>
</Value>
</Data>
<DefaultData>ResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
