Class br.musketeers.InteropMCP.Demo.RiskCheckResponse Extends Ens.Response
{

Property Status As %String;
Property Result As %String;

Storage Default
{
<Data name="RiskCheckResponseDefaultData">
<Subscript>"RiskCheckResponse"</Subscript>
<Value name="1">
<Value>Status</Value>
</Value>
<Value name="2">
<Value>Result</Value>
</Value>
</Data>
<DefaultData>RiskCheckResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
