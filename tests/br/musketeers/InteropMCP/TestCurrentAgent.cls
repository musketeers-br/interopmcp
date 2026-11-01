Class br.musketeers.InteropMCP.TestCurrentAgent Extends %UnitTest.TestCase
{

/// The gateway attributes a call to the authenticated IRIS user in secured
/// mode and to the explicit local-dev marker in demo mode. It never records
/// an empty identity.
Method TestCurrentAgentInSecuredMode() As %Status
{
    Set saved = ##class(br.musketeers.InteropMCP.Setup).GetMode()
    Set sc = ##class(br.musketeers.InteropMCP.Setup).SetMode("secured")
    If $$$ISERR(sc) Quit sc
    Set agent = ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent()
    Set sc = ##class(br.musketeers.InteropMCP.Setup).SetMode(saved)
    If $$$ISERR(sc) Quit sc
    Do $$$AssertTrue(agent '= "", "Secured mode resolves an identity")
    Do $$$AssertTrue(agent '= "local-dev", "Secured mode does not use the demo marker")
    Quit $$$OK
}

/// Demo mode is explicitly unauthenticated, so the gateway attributes every
/// call to the local-dev marker instead of an anonymous placeholder.
Method TestCurrentAgentInDemoMode() As %Status
{
    Set saved = ##class(br.musketeers.InteropMCP.Setup).GetMode()
    Set sc = ##class(br.musketeers.InteropMCP.Setup).SetMode("demo")
    If $$$ISERR(sc) Quit sc
    Set agent = ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent()
    Set sc = ##class(br.musketeers.InteropMCP.Setup).SetMode(saved)
    If $$$ISERR(sc) Quit sc
    Do $$$AssertEquals(agent, "local-dev", "Demo mode uses the local-dev marker")
    Quit $$$OK
}

/// A real identity is kept as-is - the approval replay path depends on it -
/// while an empty value or the legacy placeholder resolves to the live
/// caller.
Method TestResolveAgent() As %Status
{
    Set saved = ##class(br.musketeers.InteropMCP.Setup).GetMode()
    Set sc = ##class(br.musketeers.InteropMCP.Setup).SetMode("secured")
    If $$$ISERR(sc) Quit sc
    Set kept = ##class(br.musketeers.InteropMCP.Guardrails).ResolveAgent("agent-42")
    Set resolved = ##class(br.musketeers.InteropMCP.Guardrails).ResolveAgent("")
    Set legacy = ##class(br.musketeers.InteropMCP.Guardrails).ResolveAgent("agent")
    Set live = ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent()
    Set sc = ##class(br.musketeers.InteropMCP.Setup).SetMode(saved)
    If $$$ISERR(sc) Quit sc
    Do $$$AssertEquals(kept, "agent-42", "Explicit identity is preserved")
    Do $$$AssertEquals(resolved, live, "Empty identity resolves to the live caller")
    Do $$$AssertEquals(legacy, live, "Legacy placeholder resolves to the live caller")
    Quit $$$OK
}

/// A tool call records the caller identity on the invocation row, so the
/// audit trail names the authenticated user rather than a placeholder.
Method TestInvocationRecordsCallerIdentity() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set agent = ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent()
    Set sc = ##class(br.musketeers.InteropMCP.Invoker).Invoke("PayLookup", {"OrderId": "91001"}, agent, .invId, .resp)
    If $$$ISERR(sc) Quit sc
    Do $$$AssertTrue(invId '= "", "Invocation id returned")
    Set row = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(##class(br.musketeers.InteropMCP.Invocations).GetRowId(invId))
    Do $$$AssertEquals(row.AgentIdentity, agent, "Invocation records the caller identity")
    Quit $$$OK
}

}
