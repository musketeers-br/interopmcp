Class br.musketeers.InteropMCP.TestAgentAdapter Extends %UnitTest.TestCase
{

/// The adapter is the configuration surface of the agent: it holds the
/// document that dictates the agent's rules and the settings that bound a run.
Method TestTheAdapterCarriesTheConfiguration() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).ResolveSettings(
        "br.musketeers.InteropMCP.Demo.Production", .settings)
    Do $$$AssertTrue($$$ISOK(sc), "The agent's settings resolve from the production: "_sc)
    Do $$$AssertTrue(settings.%Get("Prompt") '= "", "The agent has a document (FR-002)")
    Do $$$AssertTrue(settings.%Get("Purpose") '= "", "The agent has a published purpose (FR-023)")
    Do $$$AssertTrue(settings.%Get("AdapterItem") '= "", "The settings name the item they came from")
    Quit $$$OK
}

/// The provider configuration never carries a credential: it references one.
Method TestTheProviderConfigurationReferencesItsCredential() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).ResolveSettings(
        "br.musketeers.InteropMCP.Demo.Production", .settings)
    Do $$$AssertTrue($$$ISOK(sc), "The agent's settings resolve from the production: "_sc)
    Set providerConfig = settings.%Get("ProviderConfig")
    Do $$$AssertTrue(providerConfig '= "", "The agent has a provider configuration")
    Do $$$AssertTrue($ZCONVERT(providerConfig,"L")[ "api_key", "The provider configuration names the credential (FR-053)")
    Do $$$AssertTrue(providerConfig[ "@{", "The provider configuration references its credential instead of storing it (FR-053)")
    Quit $$$OK
}

/// A production with no agent adapter is reported, not silently ignored.
Method TestAProductionWithoutAnAgentIsReported() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).ResolveSettings(
        "br.musketeers.InteropMCP.NoSuchProduction", .settings)
    Do $$$AssertTrue($$$ISERR(sc), "A production without an agent is reported")
    Quit $$$OK
}

/// The adapter is the class the catalogue builder recognises, and it is an
/// inbound adapter: the platform creates it for the business host that
/// references it.
Method TestTheAdapterIsAnInboundAdapter() As %Status
{
    Set isInbound = $CLASSMETHOD("br.musketeers.InteropMCP.Agent.Adapter", "%Extends", "Ens.InboundAdapter")
    Do $$$AssertTrue(isInbound, "The agent's adapter is an inbound adapter")
    Quit $$$OK
}

/// The configuration the demonstration production ships is usable: the agent
/// is published because its configuration passes the same validation every
/// operator's configuration has to pass.
Method TestTheDemonstrationsConfigurationIsUsable() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).ResolveSettings(
        "br.musketeers.InteropMCP.Demo.Production", .settings)
    Do $$$AssertTrue($$$ISOK(sc), "The agent's settings resolve from the production: "_sc)
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).Validate(settings, .reason)
    Do $$$AssertTrue($$$ISOK(sc), "The demonstration's agent configuration is usable: "_reason)
    Quit $$$OK
}

/// An agent with no document has no rules, and is rejected with a reason the
/// operator can act on.
Method TestAMissingDocumentIsRejected() As %Status
{
    Set settings = ##class(%DynamicObject).%New()
    Do settings.%Set("Prompt", "")
    Do settings.%Set("MaxIterations", 20)
    Do settings.%Set("Timeout", 120)
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).Validate(settings, .reason)
    Do $$$AssertTrue($$$ISERR(sc), "An agent with no document is rejected")
    Do $$$AssertTrue(reason '= "", "The rejection names what is wrong: "_reason)
    Do $$$AssertTrue(reason [ "Prompt", "The rejection names the setting to fix: "_reason)
    Quit $$$OK
}

/// A bound that is not positive bounds nothing, and is rejected.
Method TestABoundThatIsNotPositiveIsRejected() As %Status
{
    Set settings = ##class(%DynamicObject).%New()
    Do settings.%Set("Prompt", "Assess the supplier.")
    Do settings.%Set("MaxIterations", 0)
    Do settings.%Set("Timeout", 120)
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).Validate(settings, .reason)
    Do $$$AssertTrue($$$ISERR(sc), "An effort bound of zero is rejected")
    Do $$$AssertTrue(reason [ "MaxIterations", "The rejection names the setting to fix: "_reason)

    Do settings.%Set("MaxIterations", 20)
    Do settings.%Set("Timeout", -1)
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).Validate(settings, .reason)
    Do $$$AssertTrue($$$ISERR(sc), "A time bound that is not positive is rejected")
    Do $$$AssertTrue(reason [ "Timeout", "The rejection names the setting to fix: "_reason)
    Quit $$$OK
}

/// A credential written in the configuration is a secret in the source tree;
/// a credential referenced from the governed store is not. The second is
/// accepted, the first is rejected.
Method TestAWrittenCredentialIsRejected() As %Status
{
    Set settings = ##class(%DynamicObject).%New()
    Do settings.%Set("Prompt", "Assess the supplier.")
    Do settings.%Set("MaxIterations", 20)
    Do settings.%Set("Timeout", 120)
    Do settings.%Set("ProviderConfig", "{""model_provider"":""nim"",""api_key"":""@{env:NVIDIA_API_KEY}""}")
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).Validate(settings, .reason)
    Do $$$AssertTrue($$$ISOK(sc), "A referenced credential is accepted: "_reason)

    Do settings.%Set("ProviderConfig", "{""model_provider"":""nim"",""api_key"":""nvapi-a-written-secret""}")
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).Validate(settings, .reason)
    Do $$$AssertTrue($$$ISERR(sc), "A written credential is rejected")
    Do $$$AssertTrue(reason [ "credential", "The rejection names the problem: "_reason)
    Quit $$$OK
}

}
