/// IRIS MCP Gateway - health snapshot for operational monitoring.
/// Production-agnostic by design: the monitored production name is read from
/// the configuration global ^InteropMCP.Config("production"), set by whoever
/// bootstraps a production into this environment (for example the container
/// demo bootstrap). In an environment without any production the snapshot
/// still renders, with an empty productionName and zeroed counters - the
/// gateway core installs and runs fine with no productions at all.
/// Consumed by container health tooling, dashboards and operators; complements
/// the native Visual Trace with gateway-side counters.
Class br.musketeers.InteropMCP.Health Extends %RegisteredObject
{

/// Assembles the current snapshot:
/// - production: "configured" when the configured production is registered,
///   "stopped" otherwise or when no production is configured
/// - productionName: configured production class name, empty when none
/// - catalogSize: number of tools in the published catalog
/// - pendingApprovals: human-in-the-loop requests still undecided
/// - lastInvocationAt: reserved for invocation recency reporting
/// - logLevel: active gateway log level
ClassMethod GetStatus() As %DynamicObject
{
    Set status = ##class(%DynamicObject).%New()
    Set prodName = $Get(^InteropMCP.Config("production"), "")
    Do status.%Set("production", "stopped")
    Do status.%Set("productionName", prodName)
    Do status.%Set("catalogSize", 0)
    Do status.%Set("pendingApprovals", 0)
    Do status.%Set("lastInvocationAt", "")
    Set logLevel = "info"
    Do status.%Set("logLevel", logLevel)
    If prodName '= "" {
        Try {
            If ##class(Ens.Config.Production).%ExistsId(prodName) {
                Do status.%Set("production", "configured")
            }
        } Catch ex {
            Set tIgnored = 1
        }
    }
    Set count = 0
    Set name = ""
    For {
        Set name = $Order(^InteropMCP.Catalog(name))
        If name = "" Quit
        Set count = count + 1
    }
    Do status.%Set("catalogSize", count)
    Set pcount = 0
    Set id = ""
    For {
        Set id = $Order(^InteropMCP.ApprovalsD(id))
        If id = "" Quit
        Set ap = ##class(br.musketeers.InteropMCP.Approvals).%OpenId(id)
        If $IsObject(ap) {
            If ap.Decision = "pending" Set pcount = pcount + 1
        }
    }
    Do status.%Set("pendingApprovals", pcount)
    Quit status
}

}
