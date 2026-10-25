Class br.musketeers.InteropMCP.Demo.PayLookupResponse Extends Ens.Response
{

Property Status As %String;
Property Paid As %Boolean;
Property Amount As %Numeric;

Storage Default
{
<Data name="PayLookupResponseDefaultData">
<Subscript>"PayLookupResponse"</Subscript>
<Value name="1">
<Value>Status</Value>
</Value>
<Value name="2">
<Value>Paid</Value>
</Value>
<Value name="3">
<Value>Amount</Value>
</Value>
</Data>
<DefaultData>PayLookupResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
