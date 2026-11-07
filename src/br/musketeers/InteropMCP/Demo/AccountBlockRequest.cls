Class br.musketeers.InteropMCP.Demo.AccountBlockRequest Extends Ens.Request
{

Property CustomerId As %String [ Required ];
Property BlockType As %String;
Property Reason As %String;

Storage Default
{
<Data name="AccountBlockRequestDefaultData">
<Subscript>"AccountBlockRequest"</Subscript>
<Value name="1">
<Value>CustomerId</Value>
</Value>
<Value name="2">
<Value>BlockType</Value>
</Value>
<Value name="3">
<Value>Reason</Value>
</Value>
</Data>
<DefaultData>AccountBlockRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}