Class br.musketeers.InteropMCP.Demo.BatchRunResponse Extends Ens.Response
{

Property Status As %String;
Property JobId As %String;

Storage Default
{
<Data name="BatchRunResponseDefaultData">
<Subscript>"BatchRunResponse"</Subscript>
<Value name="1">
<Value>Status</Value>
</Value>
<Value name="2">
<Value>JobId</Value>
</Value>
</Data>
<DefaultData>BatchRunResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
