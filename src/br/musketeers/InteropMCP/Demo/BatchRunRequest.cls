Class br.musketeers.InteropMCP.Demo.BatchRunRequest Extends Ens.Request
{

Property ReportSet As %String [ Required ];

/// The invocation the run belongs to. The gateway fills it when it dispatches
/// the run, so that the business host performing the run in the background
/// can record the outcome against the invocation the caller is polling. It is
/// the gateway's own channel and is not published to the caller.
Property GatewayInvocationId As %String;

Storage Default
{
<Data name="BatchRunRequestDefaultData">
<Subscript>"BatchRunRequest"</Subscript>
<Value name="1">
<Value>ReportSet</Value>
</Value>
<Value name="2">
<Value>GatewayInvocationId</Value>
</Value>
</Data>
<DefaultData>BatchRunRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
