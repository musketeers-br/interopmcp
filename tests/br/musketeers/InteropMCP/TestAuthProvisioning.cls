Class br.musketeers.InteropMCP.TestAuthProvisioning Extends %UnitTest.TestCase
{

Method TestSecuredApplication() As %Status
{
    Set oldNs = $Namespace
    Set sc = ##class(br.musketeers.InteropMCP.Setup).Run("prod")
    Do $$$AssertStatusOK(sc, "Secured setup succeeds")
    Set $NAMESPACE = "%SYS"
    Set sc = ##class(Security.Applications).Get("/mcp/interopmcp", .p)
    Do $$$AssertStatusOK(sc, "Secured application exists")
    Do $$$AssertEquals(p("AutheEnabled"), 32, "Password authentication is enabled")
    Do $$$AssertEquals(p("Resource"), "", "Application resource is left empty")
    Do $$$AssertEquals(p("MatchRoles"), "", "No roles are granted by the application")
    Do $$$AssertEquals(p("LoginPage"), "", "Login page is empty")
    Do $$$AssertEquals(p("Type"), 18, "Application type is MCP service")
    Do $$$AssertEquals(p("DispatchClass"), "br.musketeers.InteropMCP.MCPService", "Dispatch class is the gateway service")
    Set $NAMESPACE = oldNs
    Quit $$$OK
}

}
