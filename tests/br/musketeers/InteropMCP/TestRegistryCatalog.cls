Class br.musketeers.InteropMCP.TestRegistryCatalog Extends %UnitTest.TestCase
{

/// The published catalog exposes the Business Services of the production and
/// keeps their tool names unique.
Method TestCatalog() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.Registry).ListTools(.catalog)
    If $$$ISERR(sc) Quit sc
    Set tools = catalog.%Get("tools")
    Do $$$AssertTrue(tools.%Size() >= 4, "Catalog has at least 4 tools: "_tools.%Size())
    Set found = 0
    For i = 0:1:tools.%Size() - 1 {
        Set def = tools.%Get(i)
        If def.name = "PayLookup" Set found = found + 1
    }
    Do $$$AssertEquals(found, 1, "PayLookup exposed (FR-003)")
    Quit $$$OK
}

/// Tool names are unique in the published catalog: an ambiguous catalog would
/// let one service answer for another.
Method TestDuplicateToolNames() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.Registry).ListTools(.catalog)
    If $$$ISERR(sc) Quit sc
    Set tools = catalog.%Get("tools")
    Set seen = ##class(%DynamicArray).%New()
    Set duplicates = 0
    For i = 0:1:tools.%Size() - 1 {
        Set def = tools.%Get(i)
        Set check = 0
        For j = 0:1:seen.%Size() - 1 {
            If seen.%Get(j) = def.name Set check = 1
        }
        If check Set duplicates = duplicates + 1
        Do seen.%Push(def.name)
    }
    Do $$$AssertEquals(duplicates, 0, "Catalog carries no duplicate tool names")
    Quit $$$OK
}

/// Building a catalog for an unknown production fails instead of publishing an
/// empty catalog.
Method TestUnknownProduction() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.NoSuchProduction")
    Do $$$AssertTrue($$$ISERR(sc), "Unknown production refused")
    Quit $$$OK
}

/// The agent is published beside the production's capabilities, as an agent:
/// it points at the business host that runs it and at the agent's request
/// class, and its description is the adapter's purpose.
Method TestTheAgentIsPublishedBesideTheCapabilities() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.Registry).ListTools(.catalog)
    If $$$ISERR(sc) Quit sc
    Set tools = catalog.%Get("tools")

    Set agent = ""
    Set capabilities = 0
    For i = 0:1:tools.%Size() - 1 {
        Set def = tools.%Get(i)
        If def.kind = "agent" {
            Set agent = def
        } ElseIf def.kind = "capability" {
            Set capabilities = capabilities + 1
        }
    }
    Do $$$AssertTrue(agent '= "", "The agent is published beside the capabilities (FR-022)")
    Do $$$AssertTrue(capabilities >= 4, "The capabilities are still published: "_capabilities)
    Do $$$AssertEquals(agent.serviceName, "AgentHost", "The agent points at the host that runs it (FR-020)")
    Do $$$AssertEquals(agent.requestClass, "br.musketeers.InteropMCP.Agent.Request", "The agent takes the agent's request (FR-023)")
    Do $$$AssertTrue(agent.description '= "", "The agent is published with a description (FR-023)")
    Do $$$AssertTrue(agent.classification '= "", "The agent carries a classification (FR-018)")
    Quit $$$OK
}

/// The agent's own entry is kept out of the tool surface it is given, so the
/// agent cannot call itself.
Method TestTheAgentIsNotInItsOwnToolSurface() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set methods = ##class(%Dictionary.CompiledClass).%OpenId("br.musketeers.InteropMCP.AgentTools")
    Do $$$AssertTrue($ISOBJECT(methods), "The agent's tool class is compiled")
    Set found = 0
    For i = 1:1:methods.Methods.Count() {
        If methods.Methods.GetAt(i).Name = "AgentHost" Set found = found + 1
    }
    Do $$$AssertEquals(found, 0, "The agent's own entry is not in the agent's tool surface")
    Set capabilities = 0
    For i = 1:1:methods.Methods.Count() {
        Set capabilities = capabilities + 1
    }
    Do $$$AssertTrue(capabilities >= 4, "The agent can reach the production's capabilities: "_capabilities)
    Quit $$$OK
}

/// The generated tools carry a docstring, so that the annotation a business
/// service declares reaches the caller as the tool's description.
Method TestTheGeneratedToolsCarryTheirDescription() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.Registry).GetToolDefinition("RiskCheck", .def)
    Do $$$AssertTrue($$$ISOK(sc), "RiskCheck is published: "_sc)
    Do $$$AssertTrue(def.description '= "", "The capability's description reaches the catalogue (FR-023)")
    Quit $$$OK
}

}
