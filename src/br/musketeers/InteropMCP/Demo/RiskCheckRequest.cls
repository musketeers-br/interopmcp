Class br.musketeers.InteropMCP.Demo.RiskCheckRequest Extends Ens.Request
{

Property Cnpj As %String [ Required ];
Property Scope As %String;

Storage Default
{
<Data name="RiskCheckRequestDefaultData">
<Subscript>"RiskCheckRequest"</Subscript>
<Value name="1">
<Value>Cnpj</Value>
</Value>
<Value name="2">
<Value>Scope</Value>
</Value>
</Data>
<DefaultData>RiskCheckRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
