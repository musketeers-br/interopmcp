Class br.musketeers.InteropMCP.TestE2ESmoke Extends %UnitTest.TestCase
{

/// E2E smoke: PayLookup readonly, CustomerUpdate write, AccountBlock critical -> held -> approved -> completed
Method TestE2ESmokePayLookupReadonly() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set agent = ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent()
    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("PayLookup", {"OrderId": "91001"}, agent, .proceed, .holdId, .invId, .gSc)
    If $$$ISERR(sc) Quit sc
    Set resp = ##class(br.musketeers.InteropMCP.GeneratedTools).PayLookup("91001", "")
    Set status = resp.%Get("_status")
    Do $$$AssertEquals(status, "ok", "PayLookup readonly executes ok")
    Quit $$$OK
}

Method TestE2ESmokeCustomerUpdateWrite() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set agent = ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent()
    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("CustomerUpdate", {"CustomerId": "C001", "NewAddress": "Rua Nova, 123"}, agent, .proceed, .holdId, .invId, .gSc)
    If $$$ISERR(sc) Quit sc
    Set resp = ##class(br.musketeers.InteropMCP.GeneratedTools).CustomerUpdate("C001", "Rua Nova, 123")
    Set status = resp.%Get("_status")
    Do $$$AssertEquals(status, "ok", "CustomerUpdate write executes ok")
    Quit $$$OK
}

Method TestE2ESmokeAccountBlockCriticalHeldAndApproved() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set agent = ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent()
    Set proceed = 0
    Set holdId = ""
    Set invId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("AccountBlock", {"CustomerId": "C001", "BlockType": "permanent", "Reason": "critical path"}, agent, .proceed, .holdId, .invId, .gSc)
    If $$$ISERR(sc) Quit sc
    Do $$$AssertTrue(proceed = 0, "Critical tool held")
    Do $$$AssertTrue(invId '= "", "Invocation created")
    Do $$$AssertTrue(holdId '= "", "Approval request created")
    Set sc = ##class(br.musketeers.InteropMCP.Approvals).Approve(holdId, "tester")
    If $$$ISERR(sc) Quit sc
    Set row = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(##class(br.musketeers.InteropMCP.Invocations).GetRowId(invId))
    Do $$$AssertEquals(row.Status, "completed", "Invocation completed after approval")
    Quit $$$OK
}

}
