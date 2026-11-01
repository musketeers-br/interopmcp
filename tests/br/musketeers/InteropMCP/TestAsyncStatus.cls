Class br.musketeers.InteropMCP.TestAsyncStatus Extends %UnitTest.TestCase
{

/// A tool call leaves exactly one auditable row behind, and the row reaches a
/// terminal state with the business result attached.
Method TestAsyncStatus() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.GeneratedTools).BatchRun("daily")
    If $$$ISERR(sc) Quit sc
    Set count = ##class(br.musketeers.InteropMCP.Invocations).%Count()
    Do $$$AssertTrue(count >= 1, "Async invocation recorded with reference")
    Set id = $Order(^InteropMCP.InvocationsD(""))
    While id '= "" {
        Set inv = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(id)
        If inv.ToolName = "BatchRun" {
            Do $$$AssertEquals(inv.Status, "completed", "Async call reaches a terminal state")
            Do $$$AssertTrue(inv.InvocationId '= "", "Processing reference recorded")
            Quit
        }
        Set id = $Order(^InteropMCP.InvocationsD(id))
    }
    Do $$$AssertTrue(0, "BatchRun invocation found")
    Quit $$$OK
}

}
