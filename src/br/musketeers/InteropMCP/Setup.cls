/// IRIS MCP Gateway - endpoint provisioning (pure AI HUB pattern).
/// Creates or reconciles the /mcp/interopmcp web application that dispatches
/// MCP traffic into br.musketeers.InteropMCP.MCPService. This class is
/// intentionally scoped to the endpoint and its security objects: it never
/// starts productions, never builds catalogs and never references any demo
/// asset, so the gateway core installs and runs on any instance - with or
/// without Interoperability productions - via the IPM module.
/// Only secured (prod) mode is supported: password authentication,
/// least-privilege role, no anonymous traffic.
Class br.musketeers.InteropMCP.Setup Extends %RegisteredObject
{

Parameter ResourceName = "InteropMCP_Access";

Parameter RoleName = "InteropMCPRoles";

Parameter AppPath = "/mcp/interopmcp";

/// Hardcoded to MCPService which exposes %AI.MCP.Service directly
Parameter DispatchClass = "br.musketeers.InteropMCP.MCPService";

/// Minimum grants for the production instance.
    Parameter RoleResources = "InteropMCP_Access:U,%DB_IRISAPP_CODE:R,%DB_IRISAPP_DATA:RW,%DB_IRISLIB:R,%DB_IRISTEMP:RW,%Service_SQL:U";

    /// Audit event names provisioned under the INTEROPMCP event type. The
    /// gateway writes one record for an authentication denial and one for an
    /// entitlement denial.
    Parameter AuditEvents = "AuthenticationDenied,AccessDenied";

    /// Gateway tables the gateway role reads through SQL.
    Parameter SqlTables = "Invocations,Approvals";

/// Returns the provisioned gateway mode. Always "secured".
ClassMethod GetMode() As %String
{
    Quit "secured"
}

/// Provisions the endpoint and its security objects in the calling namespace.
/// Only secured mode is supported.
ClassMethod Run(pMode As %String = "prod") As %Status
{
    Set sc = ..EnsureSecurity("secured")
    If $$$ISERR(sc) Quit sc
    Set sc = ..EnsureSqlPrivileges()
    If $$$ISERR(sc) Quit sc
    Set sc = ..ProvisionApplication("secured")
    If $$$ISERR(sc) Quit sc
    // Ensure workflow prerequisites automatically
    Set sc = ##class(br.musketeers.InteropMCP.Workflow.Setup).EnsurePrerequisites()
    If $$$ISERR(sc) Quit sc
    Quit sc
}

/// Creates or reconciles the gateway resource and role. Existing definitions
/// are preserved; missing required grants are merged into an existing role.
/// In secured mode, platform auditing must be enabled.
ClassMethod EnsureSecurity(pMode As %String = "secured") As %Status
{
    Set oldNs = $Namespace
    Set $NAMESPACE = "%SYS"
    Set sc = $$$OK
    If '##class(Security.Resources).Exists(..#ResourceName) {
        Set sc = ##class(Security.Resources).Create(..#ResourceName, "InteropMCP gateway access", "", 9)
        If $$$ISERR(sc) {
            Set $NAMESPACE = oldNs
            Quit sc
        }
    }
    If '##class(Security.Roles).Exists(..#RoleName) {
        Set sc = ##class(Security.Roles).Create(..#RoleName, "InteropMCP gateway access role", ..#RoleResources, "", 0)
        If $$$ISERR(sc) {
            Set $NAMESPACE = oldNs
            Quit sc
        }
    } Else {
        Set sc = ##class(Security.Roles).Get(..#RoleName, .props)
        If $$$ISERR(sc) {
            Set $NAMESPACE = oldNs
            Quit sc
        }
        Set resources = $Get(props("Resources"))
        For i = 1:1:$Length(..#RoleResources, ",") {
            Set grant = $Piece(..#RoleResources, ",", i)
            If grant = "" Continue
            Set found = 0
            For j = 1:1:$Length(resources, ",") {
                If $Piece(resources, ",", j) = grant Set found = 1
            }
            If 'found Set resources = resources_$Select(resources = "": "", 1: ",")_grant
        }
        Set props("Resources") = resources
        Set sc = ##class(Security.Roles).Modify(..#RoleName, .props)
        If $$$ISERR(sc) {
            Set $NAMESPACE = oldNs
            Quit sc
        }
    }
    Set sc = ##class(Security.System).Get(, .sys)
    If $$$ISERR(sc) {
        Set $NAMESPACE = oldNs
        Quit sc
    }
    If '$Get(sys("AuditEnabled"), 0) Set sc = $$$ERROR($$$GeneralError, "Secured mode requires Security.System.AuditEnabled=1")
    If $$$ISERR(sc) {
        Set $NAMESPACE = oldNs
        Quit sc
    }
    Set sc = ..EnsureAuditEvents()
    If $$$ISERR(sc) {
        Set $NAMESPACE = oldNs
        Quit sc
    }
    Set $NAMESPACE = oldNs
    Quit sc
}

/// Creates or re-enables the INTEROPMCP audit event type used for the
/// gateway's own authentication and entitlement denial records. IRIS drops
/// audit records whose event type does not exist, so the type has to be
/// provisioned before the gateway can write a denial record. Idempotent.
ClassMethod EnsureAuditEvents() As %Status
{
    Set oldNs = $Namespace
    Set $NAMESPACE = "%SYS"
    Set sc = $$$OK
    For i = 1:1:$Length(..#AuditEvents, ",") {
        Set event = $Piece(..#AuditEvents, ",", i)
        If event = "" Continue
        If '##class(Security.Events).Exists("InteropMCP", "INTEROPMCP", event) {
            Set sc = ##class(Security.Events).Create("InteropMCP", "INTEROPMCP", event, "InteropMCP "_$Select((event = "AccessDenied"): "entitlement denial", 1: "authentication denial"), 1, 1)
        } Else {
            Set sc = ##class(Security.Events).Set("InteropMCP", "INTEROPMCP", event, 1, 1)
        }
        If $$$ISERR(sc) {
            Set $NAMESPACE = oldNs
            Quit
        }
    }
    Set $NAMESPACE = oldNs
    Quit sc
}

/// Grants the gateway role the SQL privileges it needs on the gateway's own
/// tables. The audit store is read through SQL - by the status tool and by
/// the lifecycle transitions - and SQL table privileges are managed
/// separately from the database-level grants the role carries, so a caller
/// with %DB_IRISAPP_DATA rights still gets "not privileged" when it reads
/// the table through SQL. Idempotent: re-running the grant keeps the same
/// privilege set.
ClassMethod EnsureSqlPrivileges() As %Status
{
    Set sc = $$$OK
    For i = 1:1:$Length(..#SqlTables, ",") {
        Set table = $Piece(..#SqlTables, ",", i)
        If table = "" Continue
        Set stmt = ##class(%SQL.Statement).%New()
        Set sc = stmt.%Prepare("GRANT SELECT ON br_musketeers_InteropMCP."_table_" TO "_..#RoleName)
        If $$$ISERR(sc) Quit
        Set sc = stmt.%Execute()
        If $$$ISERR(sc) {
            Set text = $SYSTEM.Status.GetErrorText(sc)
            If $ZConvert(text, "U") '[ "NOT FOUND" Quit
            Set logData = ##class(%DynamicObject).%New()
            Do logData.%Set("table", table)
            Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "setup", "Gateway table not compiled yet - SQL grant skipped", logData)
        }
    }
    Quit sc
}

/// Creates or recreates the /mcp/interopmcp web application.
/// Type 18 is served by the IRIS private web server (default), not by the
/// Apache CSP Gateway.
ClassMethod ProvisionApplication(pMode As %String) As %Status
{
    Set tNs = $Namespace
    Set oldNs = $Namespace
    Set $NAMESPACE = "%SYS"
    Kill props
    Set props("DispatchClass") = ..#DispatchClass
    Set props("Type") = 18
    Set props("AutheEnabled") = 32
    Set props("Resource") = ..#ResourceName
    Set props("NameSpace") = tNs
    Set props("Name") = "IRIS InteropMCP"
    Set props("MatchRoles") = ""
    Set sc = ##class(Security.Applications).Delete(..#AppPath)
    Set sc = ##class(Security.Applications).Create(..#AppPath, .props)
    Set $NAMESPACE = oldNs
    Quit sc
}

/// Removes the /mcp/interopmcp web application. Idempotent; used by container
/// teardown and by operators decommissioning the endpoint. The resource, role
/// and demo users are intentionally left in place.
ClassMethod TearDown() As %Status
{
    Set oldNs = $Namespace
    Set $NAMESPACE = "%SYS"
    Set sc = $$$OK
    If ##class(Security.Applications).Exists(..#AppPath) {
        Set sc = ##class(Security.Applications).Delete(..#AppPath)
    }
    Set $NAMESPACE = oldNs
    Quit sc
}

}
