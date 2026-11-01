Class br.musketeers.InteropMCP.TestSchemaMapper Extends %UnitTest.TestCase
{

/// The request schema of a Business Service is mapped to the tool parameter
/// model: name, type and whether the parameter is required.
Method TestMapProperties() As %Status
{
    Set sc = $$$OK
    Set result = ##class(br.musketeers.InteropMCP.SchemaMapper).MapProperties("br.musketeers.InteropMCP.TestFixtures", .sc)
    If $$$ISERR(sc) Quit sc
    Do $$$AssertEquals(result.properties.%Size(), 3, "Fixture exposes 3 properties")
    Set found = 0
    Set iter = result.properties.%GetIterator()
    While iter.%GetNext(.idx, .pdef) {
        If pdef.name = "OrderId" {
            Set found = 1
            Do $$$AssertEquals(pdef.type, "string", "OrderId is string")
            Do $$$AssertEquals(pdef.required, 1, "OrderId required")
        }
        If pdef.name = "Active" {
            Do $$$AssertEquals(pdef.type, "boolean", "Active is boolean")
            Do $$$AssertEquals(pdef.required, 0, "Active is optional")
        }
    }
    Do $$$AssertEquals(found, 1, "OrderId mapped")
    Quit $$$OK
}

/// An unknown request class is reported as an error instead of producing an
/// empty parameter model.
Method TestMapUnknownClass() As %Status
{
    Set sc = $$$OK
    Set result = ##class(br.musketeers.InteropMCP.SchemaMapper).MapProperties("br.musketeers.InteropMCP.NoSuchRequest", .sc)
    Do $$$AssertTrue($$$ISERR(sc), "Unknown request class refused")
    Quit $$$OK
}

}
