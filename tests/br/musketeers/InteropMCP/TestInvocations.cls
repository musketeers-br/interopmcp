Class br.musketeers.InteropMCP.TestInvocations Extends %UnitTest.TestCase
{

ClassMethod CreateAndUpdateTest() As %Status
{
    Set sc = $$$OK
    Set params = {"OrderId": "88201"}
    Set invId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Invocations).CreateInvocation("PayLookup", "agent-1", params, .invId)
    If $$$ISERR(sc) Quit sc
    Do $$$AssertTrue(invId '= "", "Invocation id created")
    Set sc = ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invId, "completed", {"ok": 1})
    If $$$ISERR(sc) Quit sc
    Set inv = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(invId)
    Do $$$AssertEqual(inv.Status, "completed", "Status moved to completed")
    Do $$$AssertEqual(inv.MessageHeaderId, 0, "Header id defaults to 0")
    Quit $$$OK
}

}
