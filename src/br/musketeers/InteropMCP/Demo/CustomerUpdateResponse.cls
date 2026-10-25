Class br.musketeers.InteropMCP.Demo.CustomerUpdateResponse Extends Ens.Response
{

Property Status As %String;
Property Updated As %Boolean;

Storage Default
{
<Data name="CustomerUpdateResponseDefaultData">
<Subscript>"CustomerUpdateResponse"</Subscript>
<Value name="1">
<Value>Status</Value>
</Value>
<Value name="2">
<Value>Updated</Value>
</Value>
</Data>
<DefaultData>CustomerUpdateResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
