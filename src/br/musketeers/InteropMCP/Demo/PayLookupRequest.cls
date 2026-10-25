Class br.musketeers.InteropMCP.Demo.PayLookupRequest Extends Ens.Request
{

Property OrderId As %String [ Required ];
Property CustomerId As %String;

Storage Default
{
<Data name="PayLookupRequestDefaultData">
<Subscript>"PayLookupRequest"</Subscript>
<Value name="1">
<Value>OrderId</Value>
</Value>
<Value name="2">
<Value>CustomerId</Value>
</Value>
</Data>
<DefaultData>PayLookupRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
