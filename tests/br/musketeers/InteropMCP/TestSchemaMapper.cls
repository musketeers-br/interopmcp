Class br.musketeers.InteropMCP.TestSchemaMapper Extends %UnitTest.TestCase
{

ClassMethod MapPropertiesTest() As %Status
{
    Set sc = $$$OK
    Set result = ##class(br.musketeers.InteropMCP.SchemaMapper).MapProperties("br.musketeers.InteropMCP.TestFixtures", .sc)
    If $$$ISERR(sc) Quit sc
    Do $$$AssertEqual(result.properties.%Size(), 3, "Fixture exposes 3 properties")
    Do $$$AssertEqual(result.properties.GetAt(1).name, "OrderId", "First property is OrderId")
    Do $$$AssertEqual(result.properties.GetAt(1).type, "string", "OrderId is string")
    Do $$$AssertEqual(result.properties.GetAt(1).required, 1, "OrderId required")
    Quit $$$OK
}

}
