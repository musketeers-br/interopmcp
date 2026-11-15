Class br.musketeers.InteropMCP.Demo.Setup Extends %RegisteredObject
{

    /// The root of the demonstration's assets inside the container: the supplier
    /// invoices the production reads and the policy documents loaded into the
    /// agent's instructions. The repository is mounted read-write into the
    /// container, so the assets are found there.
    Parameter DemoRoot = "/home/irisowner/dev/src/br/musketeers/InteropMCP/Demo";

/// The REST endpoint that reaches the agent without the MCP protocol: a web
/// application of Type 2 (REST) at this path dispatches POST
/// /api/agent/assess into the demonstration's dispatch class.
    Parameter RESTAppPath = "/api/agent";

    /// The class the REST endpoint dispatches into.
    Parameter RESTDispatchClass = "br.musketeers.InteropMCP.Demo.AgentRESTService";

    /// The Python module that extracts the text of an attached PDF. It lives in
    /// the instance's Python path; the deployment installs it there.
    Parameter PDFModule = "interopmcp_pdf";

    ClassMethod Run() As %Status
    {
        Set sc = ##class(Ens.Director).StartProduction("br.musketeers.InteropMCP.Demo.Production")
        If $$$ISERR(sc) Set sc = $$$OK
        Set ^InteropMCP.Config("production") = "br.musketeers.InteropMCP.Demo.Production"
        Set buildSc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
        If $$$ISERR(buildSc) {
            Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "setup", "BuildCatalog failed during bootstrap", ##class(%DynamicObject).%New())
        }
        Set sc = ..EnsureDemoUsers()
        If $$$ISERR(sc) Quit sc
        Set sc = ..ProvisionAgentREST()
        If $$$ISERR(sc) Quit sc
        Do ..CheckPDFModule()
        Quit buildSc
    }

    /// Creates or recreates the demonstration's REST endpoint. The application
    /// carries the gateway's own resource, so the same role that reaches the
    /// MCP endpoint reaches this one, and a caller without the entitlement is
    /// turned away by the platform.
    ClassMethod ProvisionAgentREST() As %Status
    {
        // The gateway's resource and the calling namespace are resolved
        // before the namespace changes: the class that owns the resource lives
        // in the calling namespace, and the application must be dispatched
        // there too - an application in %SYS cannot reach a class that is not.
        Set tResource = ##class(br.musketeers.InteropMCP.Setup).#ResourceName
        Set tNs = $Namespace
        Set oldNs = $Namespace
        Set $NAMESPACE = "%SYS"
        Kill props
        Set props("DispatchClass") = ..#RESTDispatchClass
        Set props("Type") = 2
        Set props("AutheEnabled") = 32
        Set props("Resource") = tResource
        Set props("NameSpace") = tNs
        Set props("Name") = "IRIS InteropMCP Agent REST"
        Set props("MatchRoles") = ""
        Set sc = ##class(Security.Applications).Delete(..#RESTAppPath)
        Set sc = ##class(Security.Applications).Create(..#RESTAppPath, .props)
        Set $NAMESPACE = oldNs
        Quit sc
    }

    /// Confirms that the module that extracts the text of an attached PDF can
    /// be imported. Its absence does not stop the endpoint: an endpoint
    /// without it answers every call that carries a document with an error
    /// saying the document could not be read. The operator is told, because
    /// the cause is in the deployment, not in the request.
    ClassMethod CheckPDFModule() As %Status
    {
        Set available = 0
        Try {
            Set module = ##class(%SYSTEM.Python).Import(..#PDFModule)
            If $IsObject(module) Set available = 1
        } Catch ex {
            Set available = 0
        }
        If 'available {
            Set logData = ##class(%DynamicObject).%New()
            Do logData.%Set("module", ..#PDFModule)
            Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "setup", "The PDF extraction module is not installed; a request carrying a document will be refused", logData)
        }
        Quit $$$OK
    }


ClassMethod EnsureDemoUsers() As %Status
{
    Set password = $System.Util.GetEnviron("INTEROPMCP_DEMO_PASSWORD")
    If password = "" {
        Return $$$ERROR($$$GeneralError, "INTEROPMCP_DEMO_PASSWORD is not set; the demo bootstrap needs it to create mcp_demo and mcp_demo2")
    }
    Set oldNs = $Namespace
    Set $NAMESPACE = "%SYS"
    Set sc = ..ReconcileUser("mcp_demo", password, "InteropMCPRoles,%Service_EmbeddedPython", "InteropMCP demo user (entitled)")
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
