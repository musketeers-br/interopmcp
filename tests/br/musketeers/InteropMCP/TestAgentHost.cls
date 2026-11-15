Class br.musketeers.InteropMCP.TestAgentHost Extends %UnitTest.TestCase
{

/// The host is the production item the gateway calls: a business service, so
/// the existing invoker reaches it the way it reaches every other one.
Method TestTheHostIsABusinessService() As %Status
{
    Set isService = $CLASSMETHOD("br.musketeers.InteropMCP.Agent.Host", "%Extends", "Ens.BusinessService")
    Do $$$AssertTrue(isService, "The agent's host is a business service (FR-020)")
    Set adapter = $CLASSMETHOD("br.musketeers.InteropMCP.Agent.Host", "%GetParameter", "ADAPTER")
    Do $$$AssertTrue(adapter '= "", "The host references the agent's inbound adapter")
    Quit $$$OK
}

/// The agent's tool is published with the gateway's processing-reference
/// contract: the call answers immediately with the invocation the caller
/// polls, and the run continues in the background. The run itself is proved
/// end to end by the integration test (python/tests/test_agent_tool.py),
/// because a unit test that starts a real run would leave it holding a
/// worker of the production's pool.
Method TestTheAgentIsCalledThroughTheProcessingReference() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    Do $$$AssertTrue($$$ISOK(sc), "The catalogue builds: "_sc)

    Set def = ##class(br.musketeers.InteropMCP.Registry).GetToolDefinition("AgentHost", .agentDef)
    Do $$$AssertTrue($$$ISOK(sc), "The agent is published: "_sc)
    Do $$$AssertTrue(agentDef.async, "The agent's entry is asynchronous (FR-031)")
    Do $$$AssertTrue(agentDef.wait > 0, "The agent's entry carries a wait window")
    Quit $$$OK
}

/// The agent's tool surface holds the production's capabilities and never the
/// agent's own entry, so the agent cannot call itself.
Method TestTheAgentsToolSurfaceExcludesTheAgent() As %Status
{
    Set exists = ##class(%Dictionary.CompiledClass).%ExistsId("br.musketeers.InteropMCP.AgentTools")
    Do $$$AssertTrue(exists, "The agent's tool class exists")
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc

    Set def = ##class(br.musketeers.InteropMCP.Registry).GetToolDefinition("AgentHost", .agentDef)
    Do $$$AssertTrue($$$ISOK(sc), "The agent is published: "_sc)
    Do $$$AssertEquals(agentDef.kind, "agent", "The agent's entry is an agent, not a capability")

    Set sc = ##class(br.musketeers.InteropMCP.Registry).ListTools(.catalog)
    If $$$ISERR(sc) Quit sc
    Set tools = catalog.%Get("tools")

    Set capabilities = 0
    For i = 0:1:tools.%Size() - 1 {
        Set entry = tools.%Get(i)
        If entry.kind = "capability" Set capabilities = capabilities + 1
    }
    Do $$$AssertTrue(capabilities >= 4, "The production's capabilities are still published: "_capabilities)
    Quit $$$OK
}

}
