/// IRIS MCP Gateway - endpoint provisioning (pure AI HUB pattern).
/// Creates or recreates the /mcp/interopmcp web application that dispatches MCP
/// traffic into br.musketeers.InteropMCP.MCPService. This class is intentionally scoped to
/// the endpoint only: it never starts productions, never builds catalogs and
/// never references any demo asset, so the gateway core installs and runs on
/// any instance - with or without Interoperability productions - via the IPM
/// module.
/// Modes:
/// - dev: unauthenticated access, unrestricted role - local development and
///   the container demo only
/// - prod (any other value): platform authentication with a least-privilege
///   role (InteropMCPRoles must exist); unauthenticated traffic is rejected
/// Both Run and TearDown are idempotent (delete-then-create).
Class br.musketeers.InteropMCP.Setup Extends %RegisteredObject
{

/// Provisions the /mcp/interopmcp web application in the calling namespace.
/// The application is registered system-wide (Security.Applications in
/// %SYS) but bound to the caller namespace, so the same routine works on any
/// instance and namespace. pMode selects the authentication posture:
/// "dev" for local development, anything else for production hardening.
ClassMethod Run(pMode As %String = "dev") As %Status
{
    Set tNs = $Namespace
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Kill props
    Set props("DispatchClass") = "br.musketeers.InteropMCP.MCPService"
    Set props("Type") = 18
    Set props("NameSpace") = tNs
    Set props("Name") = "IRIS InteropMCP"
    If pMode = "dev" {
        Set props("AutheEnabled") = 64
        Set props("MatchRoles") = ":%All"
    } Else {
        Set props("AutheEnabled") = 1
        Set props("MatchRoles") = ":InteropMCPRoles"
    }
    Set sc = ##class(Security.Applications).Delete("/mcp/interopmcp")
    Set sc = ##class(Security.Applications).Create("/mcp/interopmcp", .props)
    Quit sc
}

/// Removes the /mcp/interopmcp web application. Idempotent; used by container
/// teardown and by operators decommissioning the endpoint.
ClassMethod TearDown() As %Status
{
    Set sc = ##class(Security.Applications).Delete("/mcp/interopmcp")
    Quit sc
}

}
