Class br.musketeers.InteropMCP.TestGuardrails Extends %UnitTest.TestCase
{

ClassMethod GuardrailTest() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set proceed = 0
    Set holdId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("PayLookup", {}, "agent", .proceed, .holdId, .sc)
    Do $$$Assert$$$OK(sc)
    Do $$$AssertTrue(proceed, "readonly proceeds immediately")
    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("CustomerUpdate", {}, "agent", .proceed, .holdId, .sc)
    Do $$$Assert$$$OK(sc)
    Do $$$AssertTrue(proceed, "write proceeds with authorization")
    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("RiskCheck", {}, "agent", .proceed, .holdId, .sc)
    Do $$$Assert$$$OK(sc)
    Do $$$AssertTrue('proceed, "critical held for approval")
    Do $$$AssertTrue(holdId '= "", "approval request created")
    Quit $$$OK
}
