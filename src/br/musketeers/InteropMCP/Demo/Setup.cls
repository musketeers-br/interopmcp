Class br.musketeers.InteropMCP.Demo.Setup Extends %RegisteredObject
{

ClassMethod Run() As %Status
{
    Set sc = ##class(Ens.Director).StartProduction("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Set sc = $$$OK
    Set ^InteropMCP.Config("production") = "br.musketeers.InteropMCP.Demo.Production"
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set sc = ..EnsureDemoUsers()
    Quit sc
}

ClassMethod EnsureDemoUsers() As %Status
{
    Set password = $System.Util.GetEnviron("INTEROPMCP_DEMO_PASSWORD")
    If password = "" {
        Return $$$ERROR($$$GeneralError, "INTEROPMCP_DEMO_PASSWORD is not set; the demo bootstrap needs it to create mcp_demo and mcp_demo2")
    }
    Set oldNs = $Namespace
    Set $NAMESPACE = "%SYS"
    Set sc = ..ReconcileUser("mcp_demo", password, "InteropMCPRoles", "InteropMCP demo user (entitled)")
    If $$$ISOK(sc) {
        Set sc = ..ReconcileUser("mcp_demo2", password, "", "InteropMCP demo user (unentitled)")
    }
    Set $NAMESPACE = oldNs
    Quit sc
}

ClassMethod ReconcileUser(pUser As %String, pPassword As %String, pRoles As %String, pFullName As %String) As %Status
{
    Kill props
    Set props("Password") = pPassword
    Set props("FullName") = pFullName
    Set props("Roles") = pRoles
    Set props("Enabled") = 1
    Set props("ChangePassword") = 0
    If ##class(Security.Users).Exists(pUser) {
        Quit ##class(Security.Users).Modify(pUser, .props)
    }
    Quit ##class(Security.Users).Create(pUser, .props)
}

}
