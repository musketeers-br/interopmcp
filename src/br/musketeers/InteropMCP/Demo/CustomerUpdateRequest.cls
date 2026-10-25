Class br.musketeers.InteropMCP.Demo.CustomerUpdateRequest Extends Ens.Request
{

Property CustomerId As %String [ Required ];
Property NewAddress As %String [ Required ];

Storage Default
{
<Data name="CustomerUpdateRequestDefaultData">
<Subscript>"CustomerUpdateRequest"</Subscript>
<Value name="1">
<Value>CustomerId</Value>
</Value>
<Value name="2">
<Value>NewAddress</Value>
</Value>
</Data>
<DefaultData>CustomerUpdateRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
