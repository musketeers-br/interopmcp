Class br.musketeers.InteropMCP.TestGuardrails Extends %UnitTest.TestCase
{

Method TestGuardrailDecision() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set params = ##class(%DynamicObject).%New()
    Set proceed = 0
    Set holdId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("PayLookup", params, "agent", .proceed, .holdId, .sc)
    Do $$$AssertStatusOK(sc)
    Do $$$AssertTrue(proceed, "readonly proceeds immediately")
    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("CustomerUpdate", params, "agent", .proceed, .holdId, .sc)
    Do $$$AssertStatusOK(sc)
    Do $$$AssertTrue(proceed, "write proceeds with authorization")
    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("RiskCheck", params, "agent", .proceed, .holdId, .sc)
    Do $$$AssertStatusOK(sc)
    Do $$$AssertTrue('proceed, "critical held for approval")
    Do $$$AssertTrue(holdId '= "", "approval request created")
    Quit $$$OK
}

}
