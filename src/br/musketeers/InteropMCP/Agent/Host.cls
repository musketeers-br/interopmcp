/// IRIS MCP Gateway - the business host that runs the agent.
/// This is the entry point the gateway calls, by production config item name,
/// exactly as it reaches every other business service. That is deliberate: the
/// existing invoker, guardrail, approval, and invocation path then apply to a
/// call that reaches the agent with no change at all, and the agent's own
/// actions - the capabilities it invokes - go through the same path, so the
/// classification and the human approval gate are applied to them as they are
/// to a direct caller's.
/// Responsibilities:
/// - Resolve the adapter's configuration from the production that owns it, so
///   that a revision of the agent's document takes effect on the next run.
/// - Build the agent and run it against the submitted goal.
/// - Return the agent's answer, and record an explicit outcome when the run
///   did not complete.
Class br.musketeers.InteropMCP.Agent.Host Extends Ens.BusinessService
{

/// The request the agent accepts: the caller's goal.
Parameter REQUESTCLASS = "br.musketeers.InteropMCP.Agent.Request";

/// The custom inbound adapter that carries the agent's configuration. The
/// production item is this business service; the framework creates the adapter
/// and lets it receive external goals, which are handed to the business host
/// the same way the gateway's calls are.
Parameter ADAPTER = "br.musketeers.InteropMCP.Agent.Adapter";

/// Runs the agent against the submitted goal and returns its answer.
Method OnProcessInput(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
	Set sc = $$$OK
	Set started = $ZH
	Set answer = ""
	Set status = "completed"
	Set reason = ""
	Set policy = ""
	Set ^||InteropMCP.Source = "AgentHost"
	If $Get(^||InteropMCP.AgentIdentity) = "" Set ^||InteropMCP.AgentIdentity = $USERNAME

	Set prodName = ##class(br.musketeers.InteropMCP.Registry).GetActiveProduction()
	If prodName = "" {
		Set reason = "No active production found for the agent to run in."
	}

	If reason = "" {
		// The configuration is resolved from the item this host runs as, not
		// from a scan of the production for an item that happens to carry an
		// agent adapter: each host owns the configuration of its own item.
		Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).ResolveSettings(prodName, ..%ConfigName, .settings)
		If $$$ISERR(sc) Set reason = "The agent's configuration could not be resolved from the production."
	}

	If reason = "" {
		Set sc = ##class(br.musketeers.InteropMCP.Agent.Builder).Build(settings, .agent, .sessionConfig)
		If $$$ISERR(sc) Set reason = "The agent could not be built from the adapter's configuration."
	}

	Set goal = ""
	Set invocationId = ""
	If $IsObject(pRequest) {
		Set goal = pRequest.Goal
		Try {
			Set invocationId = pRequest.GatewayInvocationId
		} Catch ex {
			Set invocationId = ""
		}
	}

	If reason = "" {
		// The run has started: the invocation says so, so that a caller
		// waiting on it can tell a run in progress from a run that was never
		// picked up. The transition is best effort - the run must not fail
		// because the bookkeeping did not go through.
		If invocationId '= "" {
			Set execSc = ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invocationId, "executing", "", "", 0)
			If $$$ISERR(execSc) {
				Set execData = ##class(%DynamicObject).%New()
				Do execData.%Set("invocationId", invocationId)
				Do execData.%Set("error", $System.Status.GetErrorText(execSc))
				Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "agent", "The invocation could not be marked as running", execData)
			}
		}
		Try {
			Set policy = ##class(br.musketeers.InteropMCP.Agent.ToolAudit).%New()
			Do agent.ToolManager.SetAuditPolicy(policy)
			Set session = agent.CreateSession(sessionConfig)
			Set llmResponse = agent.Run(session, goal)
			Set answer = llmResponse.Content
		} Catch ex {
			Set reason = "The agent could not complete the run: "_ex.DisplayString()
		}
	}

	Set caps = ##class(%DynamicArray).%New()
	If $IsObject(policy) {
		Set capSc = ..BuildCapabilities(policy, .caps)
		If $$$ISERR(capSc) Set caps = ##class(%DynamicArray).%New()
	}
	Set pResponse = ##class(br.musketeers.InteropMCP.Agent.Response).%New()
	Set pResponse.CapabilitiesUsed = caps.%ToJSON()
	Set pResponse.Retrievals = "[]"

	Set logData = ##class(%DynamicObject).%New()
	Do logData.%Set("production", prodName)
	Set adapterItem = ""
	If $IsObject(settings) {
		Try {
			Set adapterItem = settings.%Get("AdapterItem")
		} Catch ex {
			Set adapterItem = ""
		}
	}
	Do logData.%Set("adapterItem", adapterItem)
	Do logData.%Set("elapsedMs", ($ZH - started) * 100)
	Do logData.%Set("goalLength", $Length(goal))

	If reason '= "" {
		Set status = "failed"
		Set pResponse.Status = status
		Set pResponse.Answer = reason
		Do logData.%Set("status", status)
		Do logData.%Set("reason", reason)
		Do ##class(br.musketeers.InteropMCP.Log).Write("error", "agent", "Agent run failed", logData)
		// The run may be performing in a background job, in which case this is
		// the only place the outcome reaches the invocation the caller polls.
		If invocationId '= "" {
			Set respDyn = ##class(%Library.DynamicObject).%FromObject(pResponse)
			Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invocationId, "failed", respDyn, reason, 0)
		}
		// The reason is logged before the failure is raised: a business host
		// that fails does not hand its response back, so neither the response
		// nor a thrown exception carries the reason to the audit record. The
		// log is where it survives.
		Throw ##class(%Exception.General).%New(reason)
	}

	Set pResponse.Status = status
	Set pResponse.Answer = answer
	Do logData.%Set("status", status)
	Do ##class(br.musketeers.InteropMCP.Log).Write("info", "agent", "Agent run completed", logData)
	// The run may be performing in a background job: this is where the answer
	// reaches the invocation the caller is polling.
	If invocationId '= "" {
		Set respDyn = ##class(%Library.DynamicObject).%FromObject(pResponse)
		Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invocationId, "completed", respDyn, "", 0)
	}
	Quit sc
}

/// Builds the caller-facing report of the capabilities the agent invoked.
/// The audit policy records the call; the invocation store is the authority on
/// what happened to it. Each entry therefore carries the tool and arguments the
/// agent supplied, plus the lifecycle state and result the production recorded.
ClassMethod BuildCapabilities(pPolicy As br.musketeers.InteropMCP.Agent.ToolAudit, Output pCaps As %DynamicArray) As %Status
{
	Set pCaps = ##class(%DynamicArray).%New()
	If '$IsObject(pPolicy) Quit $$$OK
	Set calls = pPolicy.Calls
	If '$IsObject(calls) Quit $$$OK

	Set iter = calls.%GetIterator()
	While iter.%GetNext(.idx, .call) {
		Set entry = {}
		Do entry.%Set("tool", call.tool)
		Do entry.%Set("arguments", call.arguments)
		Do entry.%Set("durationMs", +call.durationMs)
		Do entry.%Set("invocationId", "")
		Do entry.%Set("approvalId", "")
		Do entry.%Set("targetTool", "")
		Do entry.%Set("messageHeaderId", 0)
		Do entry.%Set("status", "")
		Do entry.%Set("response", "")
		Do entry.%Set("error", "")

		Set resultJson = call.resultJson
		If resultJson '= "" {
			Set result = ""
			Try {
				Set result = ##class(%DynamicObject).%FromJSON(resultJson)
			} Catch ex {
				Set result = ""
			}
			If $IsObject(result) {
				Set invocationId = result.%Get("invocationId")
				If invocationId '= "" Do entry.%Set("invocationId", invocationId)
				Set approvalId = result.%Get("approvalId")
				If approvalId '= "" Do entry.%Set("approvalId", approvalId)
				Set toolStatus = result.%Get("_status")
				If toolStatus '= "" Do entry.%Set("status", toolStatus)
			}
		}

		// CreateWorkflowTask is a meta tool: the invocation it produced belongs
		// to the target capability, not to the request for approval.
		If call.tool = "CreateWorkflowTask" {
			Set targetTool = ""
			Try {
				Set targetTool = call.arguments.%Get("pToolName")
			} Catch ex {
				Set targetTool = ""
			}
			If targetTool '= "" Do entry.%Set("targetTool", targetTool)
		}

		Set invocationId = entry.%Get("invocationId")
		If invocationId '= "" {
			Set inv = ..OpenInvocation(invocationId)
			If $IsObject(inv) {
				Do entry.%Set("status", inv.Status)
				Do entry.%Set("messageHeaderId", +inv.MessageHeaderId)
				If inv.ErrorMessage '= "" Do entry.%Set("error", inv.ErrorMessage)
				If inv.Result '= "" {
					Set response = inv.Result
					Try {
						Set response = ##class(%DynamicObject).%FromJSON(inv.Result)
					} Catch ex {
						Set response = inv.Result
					}
					Do entry.%Set("response", response)
				}
			}
		}

		If entry.%Get("status") = "" {
			If call.ok {
				Do entry.%Set("status", "completed")
			} Else {
				Do entry.%Set("status", "failed")
			}
		}
		If entry.%Get("status") = "denied" Do entry.%Set("error", call.error)
		Do pCaps.%Push(entry)
	}
	Do ..TrimCapabilities(.pCaps)
	Quit $$$OK
}

ClassMethod OpenInvocation(pInvocationId As %String) As br.musketeers.InteropMCP.Invocations
{
	Set rid = ##class(br.musketeers.InteropMCP.Invocations).GetRowId(pInvocationId)
	If rid = "" Quit ""
	Quit ##class(br.musketeers.InteropMCP.Invocations).%OpenId(rid)
}

/// Keeps the agent's response inside the audit store's string budget. The full
/// tool responses remain in each tool invocation; the run-level summary keeps a
/// marker instead of silently losing the whole entry.
ClassMethod TrimCapabilities(ByRef pCaps As %DynamicArray) As %Status
{
	If '$IsObject(pCaps) Quit $$$OK
	If $Length(pCaps.%ToJSON()) <= 30000 Quit $$$OK
	Set iter = pCaps.%GetIterator()
	While iter.%GetNext(.idx, .entry) {
		Do entry.%Set("truncated", 1)
		Do entry.%Set("response", "")
		If $Length(pCaps.%ToJSON()) <= 30000 Quit
	}
	Quit $$$OK
}

}
