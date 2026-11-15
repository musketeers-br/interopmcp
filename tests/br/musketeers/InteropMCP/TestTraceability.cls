Class br.musketeers.InteropMCP.TestTraceability Extends %UnitTest.TestCase
{

Method TestTraceability() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.GeneratedTools).PayLookup("88201", "C-1")
    If $$$ISERR(sc) Quit sc
    Set count = 0
    Set id = $Order(^InteropMCP.InvocationsD(""))
    While id '= "" {
        Set count = count + 1
        Set id = $Order(^InteropMCP.InvocationsD(id))
    }
    Do $$$AssertTrue(count >= 1, "Invocation recorded (FR-010)")
    Set id = $Order(^InteropMCP.InvocationsD(""))
    Set found = 0
    While id '= "" && 'found {
        Set inv = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(id)
        If inv.ToolName = "PayLookup" {
            Set found = 1
            Do $$$AssertEquals(inv.Status, "completed", "Invocation reached completed")
            Do $$$AssertTrue(inv.StartedAt '= "", "Timestamp recorded")
            Do $$$AssertTrue(inv.AgentIdentity '= "", "Caller identity recorded")
            Do $$$AssertTrue(inv.Result '= "", "Business result recorded")
        }
        Set id = $Order(^InteropMCP.InvocationsD(id))
    }
    Quit $$$OK
}

}
