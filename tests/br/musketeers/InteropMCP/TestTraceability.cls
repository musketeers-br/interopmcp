Class br.musketeers.InteropMCP.TestTraceability Extends %UnitTest.TestCase
{

ClassMethod TraceTest() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.GeneratedTools).PayLookup("88201", "C-1")
    If $$$ISERR(sc) Quit sc
    Set count = ##class(br.musketeers.InteropMCP.Invocations).%Count()
    Do $$$AssertTrue(count >= 1, "Invocation recorded (FR-010)")
    Set id = ""
    Set id = $Order(^InteropMCP.InvocationsD(id))
    While id '= "" {
        Set inv = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(id)
        If inv.ToolName = "PayLookup" {
            Do $$$AssertEqual(inv.Status, "completed", "Invocation reached completed")
            Do $$$AssertTrue(inv.StartedAt '= "", "Timestamp recorded")
            Quit
        }
        Set id = $Order(^InteropMCP.InvocationsD(id))
    }
    Quit $$$OK
}
