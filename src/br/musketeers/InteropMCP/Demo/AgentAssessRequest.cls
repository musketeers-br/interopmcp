/// IRIS MCP Gateway - the demonstration's REST request for the agent.
/// Carries what the caller submits to the agent's REST endpoint: the goal it
/// wants the agent to pursue, the supplier it is about, and - optionally - the
/// document it is attaching, as base64.
/// The goal is required and is never chosen by the endpoint: the caller says
/// what it wants, and an empty goal is answered with an error rather than
/// with a goal the endpoint invented.
Class br.musketeers.InteropMCP.Demo.AgentAssessRequest Extends Ens.Request
{

/// What the caller wants the agent to do, in plain language. Required.
Property Goal As %String(MAXLEN = 64000) [ Required ];

/// The supplier the request is about, when the caller states it. Carried
/// along with the goal so that the agent does not have to find it in the
/// document.
Property CNPJ As %String(MAXLEN = 64);

/// The attached document, as base64. The endpoint extracts its text and
/// delivers it to the agent: the agent reads text, not binary. A document
/// carried as base64 grows by a third, so the length is the platform's
/// maximum string length.
Property DocumentBase64 As %String(MAXLEN = 3600000);

Storage Default
{
<Data name="AgentAssessRequestDefaultData">
<Subscript>"AgentAssessRequest"</Subscript>
<Value name="1">
<Value>Goal</Value>
</Value>
<Value name="2">
<Value>CNPJ</Value>
</Value>
<Value name="3">
<Value>DocumentBase64</Value>
</Value>
</Data>
<DefaultData>AgentAssessRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
