Class br.musketeers.InteropMCP.TestGeneratedTools Extends %UnitTest.TestCase
{

Method TestListAndCall() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.GeneratedTools).PayLookup("88201", "C-1")
    Do $$$AssertStatusOK(sc, "PayLookup executed via generated tool")
    Quit $$$OK
}

Method TestCatalogRefresh() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).SetEnabled("CustomerUpdate", 0)
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.Registry).SetEnabled("CustomerUpdate", 1)
    Quit sc
}

}
