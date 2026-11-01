Class br.musketeers.InteropMCP.TestRegistryCatalog Extends %UnitTest.TestCase
{

/// The published catalog exposes the Business Services of the production and
/// keeps their tool names unique.
Method TestCatalog() As %Status
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
    Do $$$AssertEquals(found, 1, "PayLookup exposed (FR-003)")
    Quit $$$OK
}

/// Tool names are unique in the published catalog: an ambiguous catalog would
/// let one service answer for another.
Method TestDuplicateToolNames() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set tools = ##class(%DynamicArray).%New()
    Set sc = ##class(br.musketeers.InteropMCP.Registry).ListTools(.tools)
    If $$$ISERR(sc) Quit sc
    Set seen = ##class(%DynamicArray).%New()
    Set duplicates = 0
    Set iter = tools.%GetIterator()
    While iter.%GetNext(.idx, .def) {
        Set check = 0
        Set inner = seen.%GetIterator()
        While inner.%GetNext(.sidx, .sname) {
            If sname = def.name Set check = 1
        }
        If check Set duplicates = duplicates + 1
        Do seen.%Push(def.name)
    }
    Do $$$AssertEquals(duplicates, 0, "Catalog carries no duplicate tool names")
    Quit $$$OK
}

/// Building a catalog for an unknown production fails instead of publishing an
/// empty catalog.
Method TestUnknownProduction() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.NoSuchProduction")
    Do $$$AssertTrue($$$ISERR(sc), "Unknown production refused")
    Quit $$$OK
}

}
