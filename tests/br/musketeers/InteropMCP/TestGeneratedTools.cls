Class br.musketeers.InteropMCP.TestGeneratedTools Extends %UnitTest.TestCase
{

ClassMethod ListAndCallTest() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.GeneratedTools).PayLookup("88201", "C-1")
    Do $$$Assert$$$OK(sc, "PayLookup executed via generated tool")
    Quit $$$OK
}

ClassMethod CatalogRefreshTest() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).SetEnabled("CustomerUpdate", 0)
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.Registry).SetEnabled("CustomerUpdate", 1)
    Quit sc
}

}
