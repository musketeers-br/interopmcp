Class br.musketeers.InteropMCP.Demo.BatchRunRequest Extends Ens.Request
{

Property ReportSet As %String [ Required ];

Storage Default
{
<Data name="BatchRunRequestDefaultData">
<Subscript>"BatchRunRequest"</Subscript>
<Value name="1">
<Value>ReportSet</Value>
</Value>
</Data>
<DefaultData>BatchRunRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
