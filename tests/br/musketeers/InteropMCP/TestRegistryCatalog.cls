Class br.musketeers.InteropMCP.TestRegistryCatalog Extends %UnitTest.TestCase
{

ClassMethod CatalogTest() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set tools = ##class(%DynamicArray).%New()
    Set sc = ##class(br.musketeers.InteropMCP.Registry).ListTools(.tools)
    If $$$ISERR(sc) Quit sc
    Do $$$AssertTrue(tools.Size() >= 4, "Catalog has at least 4 tools: "_tools.Size())
    Set found = 0
    Set iter = tools.%GetIterator()
    While iter.%GetNext(.idx, .def) {
        If def.name = "PayLookup" Set found = found + 1
    }
    Do $$$AssertEqual(found, 1, "PayLookup exposed (FR-003)")
    Quit $$$OK
}

ClassMethod DuplicateTest() As %Status
{
    Set sc = $$$OK
    Quit sc
}

}
