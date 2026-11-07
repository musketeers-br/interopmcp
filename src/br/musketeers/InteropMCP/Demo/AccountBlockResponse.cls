Class br.musketeers.InteropMCP.Demo.AccountBlockResponse Extends Ens.Response
{

Property Status As %String;
Property BlockedAt As %String;

Storage Default
{
<Data name="AccountBlockResponseDefaultData">
<Subscript>"AccountBlockResponse"</Subscript>
<Value name="1">
<Value>Status</Value>
</Value>
<Value name="2">
<Value>BlockedAt</Value>
</Value>
</Data>
<DefaultData>AccountBlockResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}