Class br.musketeers.InteropMCP.TestInvocations Extends %UnitTest.TestCase
{

/// A recorded invocation can be located by its public id, carries the caller
/// identity and moves through its lifecycle states.
Method TestCreateAndUpdate() As %Status
{
    Set params = {"OrderId": "88201"}
    Set invId = ""
    Set rowId = ##class(br.musketeers.InteropMCP.Invocations).CreateInvocation("PayLookup", "agent-1", params, .invId)
    Do $$$AssertTrue(invId '= "", "Invocation id created")
    Set sc = ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invId, "completed", {"ok": 1})
    Do $$$AssertStatusOK(sc, "Status transition accepted")
    Set rid = ##class(br.musketeers.InteropMCP.Invocations).GetRowId(invId)
    Do $$$AssertTrue(rid '= "", "Invocation row found by public id")
    Set inv = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(rid)
    Do $$$AssertEquals(inv.Status, "completed", "Status moved to completed")
    Do $$$AssertEquals(inv.AgentIdentity, "agent-1", "Caller identity recorded")
    Do $$$AssertTrue((inv.MessageHeaderId = 0) || (inv.MessageHeaderId = ""), "Header id defaults to 0")
    Do $$$AssertTrue(inv.StartedAt '= "", "Start timestamp recorded")
    Quit $$$OK
}

/// An unknown invocation id is refused instead of silently accepted.
Method TestUpdateUnknownInvocation() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus("00000000-0000-0000-0000-000000000000", "completed", {"ok": 1})
    Do $$$AssertTrue($$$ISERR(sc), "Unknown invocation refused")
    Quit $$$OK
}

/// The status tool reads the same row the audit store wrote.
Method TestStatusQueryFindsInvocation() As %Status
{
    Set invId = ""
    Set rowId = ##class(br.musketeers.InteropMCP.Invocations).CreateInvocation("PayLookup", "agent-2", {"OrderId": "88202"}, .invId)
    Set sc = ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invId, "completed", {"ok": 1})
    Do $$$AssertStatusOK(sc, "Status transition accepted")
    Set result = ##class(br.musketeers.InteropMCP.InvocationStatusTools).GetInvocationStatus(invId)
    Do $$$AssertEquals(result.%Get("row_count"), 1, "Status query returns one row")
    Set iter = result.%Get("rows").%GetIterator()
    Do iter.%GetNext(.idx, .row)
    Do $$$AssertEquals(row.%Get("AgentIdentity"), "agent-2", "Status query exposes the caller identity")
    Do $$$AssertEquals(row.%Get("Status"), "completed", "Status query exposes the lifecycle state")
    Quit $$$OK
}

}
