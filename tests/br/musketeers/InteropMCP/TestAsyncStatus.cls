Class br.musketeers.InteropMCP.TestAsyncStatus Extends %UnitTest.TestCase
{

ClassMethod AsyncTest() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.GeneratedTools).BatchRun("daily")
    If $$$ISERR(sc) Quit sc
    Set count = ##class(br.musketeers.InteropMCP.Invocations).%Count()
    Do $$$AssertTrue(count >= 1, "Async invocation recorded with reference")
    Set id = ""
    Set id = $Order(^InteropMCP.InvocationsD(id))
    While id '= "" {
        Set inv = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(id)
        If inv.ToolName = "BatchRun" {
            Do $$$AssertEqual(inv.Status, "received", "Async accepted immediately")
            Quit
        }
        Set id = $Order(^InteropMCP.InvocationsD(id))
    }
    Quit $$$OK
}
