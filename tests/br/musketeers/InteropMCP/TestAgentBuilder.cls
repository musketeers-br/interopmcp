Class br.musketeers.InteropMCP.TestAgentBuilder Extends %UnitTest.TestCase
{

/// The reachable scope narrows what the agent may reach. A capability inside
/// the scope is in the agent's own tool surface; a capability outside it is
/// not; and the agent's own entry never is, so the agent cannot call itself.
Method TestTheScopeNarrowsTheAgentsToolSurface() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    Do $$$AssertTrue($$$ISOK(sc), "The catalogue builds: "_sc)

    Set sc = ##class(br.musketeers.InteropMCP.Registry).GenerateAgentToolsClass("PayLookup", "AgentHost")
    Do $$$AssertTrue($$$ISOK(sc), "The agent's tool surface is generated with a scope: "_sc)

    Set names = ..MethodNames("br.musketeers.InteropMCP.AgentTools")
    Do $$$AssertTrue(names [ " PayLookup", "A capability inside the scope is reachable by the agent: "_names)
    Do $$$AssertTrue(names '[" RiskCheck", "A capability outside the scope is not reachable by the agent: "_names)
    Do $$$AssertTrue(names '[" AgentHost", "The agent cannot call itself: "_names)

    // The live agent's own surface is restored, so the test leaves the
    // deployment as it found it.
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    Do $$$AssertTrue($$$ISOK(sc), "The catalogue is rebuilt: "_sc)
    Quit $$$OK
}

/// An empty scope means every published capability of the production: the
/// agent's surface then holds the capabilities and nothing else.
Method TestAnEmptyScopeMeansEveryCapability() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    Do $$$AssertTrue($$$ISOK(sc), "The catalogue builds: "_sc)

    Set sc = ##class(br.musketeers.InteropMCP.Registry).GenerateAgentToolsClass("", "AgentHost")
    Do $$$AssertTrue($$$ISOK(sc), "The agent's tool surface is generated without a scope: "_sc)

    Set names = ..MethodNames("br.musketeers.InteropMCP.AgentTools")
    Do $$$AssertTrue(names [ " PayLookup", "The capabilities are reachable by the agent: "_names)
    Do $$$AssertTrue(names [ " RiskCheck", "The capabilities are reachable by the agent: "_names)
    Do $$$AssertTrue(names '[" AgentHost", "The agent cannot call itself: "_names)

    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    Do $$$AssertTrue($$$ISOK(sc), "The catalogue is rebuilt: "_sc)
    Quit $$$OK
}

/// The names of a class's methods, each preceded by a space, so that a name
/// is never matched inside another one.
ClassMethod MethodNames(pClassName As %String) As %String
{
    Set names = ""
    Set cd = ##class(%Dictionary.CompiledClass).%OpenId(pClassName)
    If '$IsObject(cd) Quit names
    For i = 1:1:cd.Methods.Count() {
        Set m = cd.Methods.GetAt(i)
        Set names = names _ " "_m.Name
    }
    Quit names
}

/// The run's bounds reach the session the run is made in. The effort bound is
/// the agent's own, and the time bound is the session's wall-clock budget:
/// a bound that is validated but never applied bounds nothing.
Method TestTheBoundsReachTheSession() As %Status
{
    Set settings = ##class(%DynamicObject).%New()
    Do settings.%Set("Prompt", "You are a risk analyst.")
    Do settings.%Set("ProviderConfig", {"model_provider":"nim","base_url":"https://example.invalid/v1","api_key":"@{env:NVIDIA_API_KEY}"}.%ToJSON())
    Do settings.%Set("MaxIterations", 7)
    Do settings.%Set("Timeout", 45)

    Set sc = ##class(br.musketeers.InteropMCP.Agent.Builder).Build(settings, .agent, .sessionConfig)
    Do $$$AssertTrue($$$ISOK(sc), "The agent builds: "_sc)
    Do $$$AssertEquals(7, agent.MaxIterations, "The effort bound reaches the agent.")
    Do $$$AssertEquals(45000, sessionConfig.%Get("timeout_ms"), "The time bound reaches the session.")

    // An operator who sets no bound gets the documented default, not an
    // unbounded run.
    Set settings = ##class(%DynamicObject).%New()
    Do settings.%Set("Prompt", "You are a risk analyst.")
    Do settings.%Set("ProviderConfig", {"model_provider":"nim","base_url":"https://example.invalid/v1","api_key":"@{env:NVIDIA_API_KEY}"}.%ToJSON())

    Set sc = ##class(br.musketeers.InteropMCP.Agent.Builder).Build(settings, .agent, .sessionConfig)
    Do $$$AssertTrue($$$ISOK(sc), "The agent builds without explicit bounds: "_sc)
    Do $$$AssertEquals(20, agent.MaxIterations, "The default effort bound applies.")
    Do $$$AssertEquals(120000, sessionConfig.%Get("timeout_ms"), "The default time bound applies.")

    Quit $$$OK
}

}
