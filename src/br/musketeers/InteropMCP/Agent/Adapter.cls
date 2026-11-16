/// IRIS MCP Gateway - the custom inbound adapter that gives a production an agent.
/// This is the component an operator attaches to a production that already
/// works, and the component they configure. It owns the agent's
/// configuration - the document that dictates the agent's rules, the model,
/// the capabilities the agent may reach, the bounds of a run, and the
/// knowledge it retrieves - and it is also the door through which the agent
/// receives work.
/// Responsibilities:
/// - Hold the agent's configuration as adapter settings an operator sets on
///   the production item, so that the configuration lives in the production
///   and is changed in one place.
/// - Resolve that configuration at run time, so that a revision takes effect
///   on the next run without the production's components being redeployed.
/// - Poll the queue of work and hand each item to the business host that
///   runs the agent.
/// The adapter is referenced by the business host's ADAPTER parameter: a
/// production item is a business host, and the framework creates the adapter
/// for it. The agent runs inside the production, in that host.
/// The adapter is one door of the item, not the only one. A caller that
/// reaches the business service directly - the gateway, or any application
/// that fires a business service - reaches the same agent by the same
/// route the adapter uses. The adapter is the pull door: it waits for work
/// that was produced elsewhere and carries it in.
Class br.musketeers.InteropMCP.Agent.Adapter Extends Ens.InboundAdapter
{

/// The class of this adapter, used by the catalogue builder to recognise the
/// production item that carries an agent.
Parameter AdapterClass = "br.musketeers.InteropMCP.Agent.Adapter";

/// The authority the gateway applies to a call that reaches the agent. The
/// agent's own actions are classified individually, by the classification of
/// the capability they invoke.
Parameter AIGATEWAY = "write";

/// The agent's document: the plain-language instructions that govern the
/// agent's role, its conduct, and what it must never do. Required.
Property Prompt As %VarString;

/// What the agent is for, in one sentence. Published as the agent tool's
/// description so that a caller can discover what the agent is for without
/// reading its document.
Property Purpose As %VarString;

/// The language model the agent uses. Empty means the platform default.
Property Model As %String;

/// The provider settings, as a JSON object. Credentials are referenced from
/// the governed configuration store or the environment, never written here.
Property ProviderConfig As %String;

/// The production's own parameters, as a JSON object: the settings that
/// belong to this production rather than to the gateway - the files its
/// rules name, the records its agent must consult. The gateway carries them
/// and makes them available to the agent's instructions; it does not
/// interpret the keys, which belong to the production.
Property ProductionConfig As %String;

/// The published capabilities the agent may reach, comma separated. Empty
/// means every published capability of the production.
Property AgentTools As %String;

/// The effort bound for one run, in the agent's own iterations.
Property MaxIterations As %Integer [ InitialExpression = 20 ];

/// The elapsed-time bound for one run, in seconds. The policy documents in
/// the prompt make a run slower than the old 120s default.
Property Timeout As %Integer [ InitialExpression = 240 ];

/// The indexed knowledge the agent retrieves. Empty means no retrieval.
Property KnowledgeBase As %String;

/// Directory or comma-separated list of policy documents loaded into the
/// agent's instructions. Empty means no policy documents beyond the Prompt.
Property PolicyDocs As %String;

/// How long a run may hold a queued item before the item is considered
/// abandoned, in seconds. A run that outlives its lease without finishing -
/// because the container restarted, or the job was killed - would otherwise
/// leave the item claimed forever, with nobody to release it. Zero means the
/// default lease.
Property LeaseSeconds As %Integer [ InitialExpression = 300 ];

/// The settings an operator sets on the production item. CallInterval is
/// inherited from the platform's inbound adapter and is listed here so that
/// the polling interval stays adjustable from the Production UI.
Parameter SETTINGS = "Prompt:Basic,Purpose:Basic,Model:Basic,ProviderConfig:Basic,AgentTools:Basic,MaxIterations:Basic,Timeout:Basic,KnowledgeBase:Basic,PolicyDocs:Basic,ProductionConfig:Basic,CallInterval:Basic,LeaseSeconds:Basic";

/// The lease used when the operator has not set one.
Parameter DefaultLeaseSeconds = 300;

/// Polls the queue of work and hands one item to the business host that runs
/// the agent. This is the adapter's contract with the platform: the framework
/// calls this method on every interval, and the work reaches the business
/// service through it.
/// One item is taken per cycle. A run of the agent takes as long as it takes,
/// and taking a second item in the same cycle would hold the polling job for
/// the sum of both - the queue would drain at the speed of the agent, which
/// is the point of polling it.
Method OnTask() As %Status
{
    Set sc = $$$OK

    Set lease = ..LeaseSeconds
    If lease <= 0 Set lease = ..#DefaultLeaseSeconds

    // Items whose run was abandoned are failed first, so that a caller
    // waiting on one is not left waiting for work that will never run.
    Set abandoned = ##class(%DynamicArray).%New()
    Set reapSc = ##class(br.musketeers.InteropMCP.Agent.Queue).Reap(lease, .abandoned)
    If $$$ISERR(reapSc) {
        Do ..WriteLog("warn", "The abandoned work items could not be swept.", reapSc)
    } ElseIf abandoned.size() > 0 {
        Set logData = ##class(%DynamicObject).%New()
        Do logData.%Set("items", abandoned.%ToJSON())
        Do ..WriteLog("warn", "Work items were abandoned by a run that did not finish.", "", logData)
    }

    Set entry = ""
    Set queueId = ""
    Set claimSc = ##class(br.musketeers.InteropMCP.Agent.Queue).Claim(.entry, .queueId)
    If $$$ISERR(claimSc) {
        Do ..WriteLog("error", "The queued work could not be claimed.", claimSc)
        Set sc = claimSc
    } ElseIf $IsObject(entry) {
        Set sc = ..Run(entry, queueId)
    }

    // The polling loop must be told to wait for the next interval. The
    // business service clears this flag when it processes an input, and a
    // polling loop that does not get it back stops.
    Set ..BusinessHost.%WaitForNextCallInterval = 1
    Quit sc
}

/// Runs one queued item: restores the context that produced it, hands the
/// goal to the agent, and records the outcome on the queue.
Method Run(pEntry As %DynamicObject, pQueueId As %String) As %Status
{
    Set sc = $$$OK
    Set goal = pEntry.%Get("goal")
    Set invocationId = pEntry.%Get("invocationId")
    Set agentIdentity = pEntry.%Get("agentIdentity")
    Set source = pEntry.%Get("source")
    Set sessionId = pEntry.%Get("sessionId")

    // Restore the caller's context so the agent's own calls are attributed
    // to the caller that started the run, and the run's trace belongs to it.
    If agentIdentity '= "" Set ^||InteropMCP.AgentIdentity = agentIdentity
    If source '= "" Set ^||InteropMCP.Source = source
    // Each run belongs to its own session: the polling job is long-lived, so
    // the session is cleared rather than inherited from the previous run.
    If sessionId '= "" {
        Set ^||InteropMCP.SessionId = sessionId
    } Else {
        Kill ^||InteropMCP.SessionId
    }

    // The adapter runs the agent: the configuration is resolved from the item
    // the adapter belongs to, and the outcome is recorded in the invocation
    // store by the run itself.
    Set response = ""
    Set sc = ..ExecuteAgent(..BusinessHost.%ConfigName, goal, invocationId, source, .response)

    If $$$ISERR(sc) {
        Set reason = ""
        If $IsObject(response) {
            Try {
                Set reason = response.Answer
            } Catch ex {
                Set reason = ""
            }
        }
        If reason = "" Set reason = $SYSTEM.Status.GetErrorText(sc)
        Set logData = ##class(%DynamicObject).%New()
        Do logData.%Set("queueId", pQueueId)
        Do logData.%Set("invocationId", invocationId)
        Do logData.%Set("reason", reason)
        Do ..WriteLog("error", "The queued run did not complete.", "", logData)
        Do ##class(br.musketeers.InteropMCP.Agent.Queue).Complete(pQueueId, "ERROR", reason)
        Quit sc
    }

    Set logData = ##class(%DynamicObject).%New()
    Do logData.%Set("queueId", pQueueId)
    Do logData.%Set("invocationId", invocationId)
    Do ..WriteLog("info", "The queued run completed.", "", logData)
    Do ##class(br.musketeers.InteropMCP.Agent.Queue).Complete(pQueueId, "COMPLETED", "")
    Quit sc
}

/// Runs the agent against a goal and records the outcome. This is the whole
/// of the agent's execution: the configuration is resolved from the item the
/// agent runs as, the agent is built from that configuration, the run is
/// executed, the capabilities the agent invoked are reported, and the outcome
/// is recorded in the invocation store.
/// Both doors of the production item reach the agent through this method: the
/// adapter, for the work it polls out of the queue, and the business host,
/// for a call that reaches the business service directly. One implementation,
/// so the two cannot drift apart.
/// Outputs pResponse: the agent's response - its answer, the capabilities it
/// invoked, and the outcome of the run. A run that failed carries the reason
/// as its answer, and the returned status is the failure.
ClassMethod ExecuteAgent(pConfigName As %String, pGoal As %String, pInvocationId As %String, pSource As %String, Output pResponse As Ens.Response) As %Status
{
    Set sc = $$$OK
    Set started = $ZH
    Set answer = ""
    Set status = "completed"
    Set reason = ""
    Set policy = ""
    Set agent = ""
    Set sessionConfig = ""

    // The origin of the work and the identity of the caller are the context
    // the agent's own calls are attributed to. The door that opened the run
    // names the origin; the identity is already set by the caller when there
    // is one.
    If pSource '= "" Set ^||InteropMCP.Source = pSource
    If $Get(^||InteropMCP.AgentIdentity) = "" Set ^||InteropMCP.AgentIdentity = $USERNAME

    // Resolve the agent's configuration from the item it runs as: each host
    // owns the configuration of its own item.
    Set prodName = ##class(br.musketeers.InteropMCP.Registry).GetActiveProduction()
    Set settings = ""
    Set sc = ..ResolveSettings(prodName, pConfigName, .settings)
    If $$$ISERR(sc) {
        Set reason = "The agent's configuration could not be resolved from the production."
    }

    If reason = "" {
        Set sc = ##class(br.musketeers.InteropMCP.Agent.Builder).Build(settings, .agent, .sessionConfig)
        If $$$ISERR(sc) Set reason = "The agent could not be built from the adapter's configuration."
    }

    If reason = "" {
        // The run has started: the invocation says so, so that a caller
        // waiting on it can tell a run in progress from a run that was never
        // picked up. The transition is best effort - the run must not fail
        // because the bookkeeping did not go through.
        If pInvocationId '= "" {
            Set execSc = ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "executing", "", "", 0)
            If $$$ISERR(execSc) {
                Set execData = ##class(%DynamicObject).%New()
                Do execData.%Set("invocationId", pInvocationId)
                Do execData.%Set("error", $System.Status.GetErrorText(execSc))
                Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "agent", "The invocation could not be marked as running", execData)
            }
        }
        Try {
            Set policy = ##class(br.musketeers.InteropMCP.Agent.ToolAudit).%New()
            Do agent.ToolManager.SetAuditPolicy(policy)
            Set session = agent.CreateSession(sessionConfig)
            Set llmResponse = agent.Run(session, pGoal)
            Set answer = llmResponse.Content
        } Catch ex {
            Set reason = "The agent could not complete the run: "_ex.DisplayString()
        }
    }

    // Build the caller-facing report of what the agent did.
    Set caps = ##class(%DynamicArray).%New()
    If $IsObject(policy) {
        Set capSc = ..BuildCapabilities(policy, .caps)
        If $$$ISERR(capSc) Set caps = ##class(%DynamicArray).%New()
    }
    Set response = ##class(br.musketeers.InteropMCP.Agent.Response).%New()
    Set response.CapabilitiesUsed = caps.%ToJSON()
    Set response.Retrievals = "[]"

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
    Do logData.%Set("goalLength", $Length(pGoal))

    If reason '= "" {
        Set status = "failed"
        Set response.Status = status
        Set response.Answer = reason
        Do logData.%Set("status", status)
        Do logData.%Set("reason", reason)
        Do ##class(br.musketeers.InteropMCP.Log).Write("error", "agent", "Agent run failed", logData)
        // The run may be performing in a background job, in which case this is
        // the only place the outcome reaches the invocation the caller polls.
        If pInvocationId '= "" {
            Set respDyn = ##class(%Library.DynamicObject).%FromObject(response)
            Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "failed", respDyn, reason, 0)
        }
        Set pResponse = response
        Quit $$$ERROR($$$GeneralError, reason)
    }

    Set response.Status = status
    Set response.Answer = answer
    Do logData.%Set("status", status)
    Do ##class(br.musketeers.InteropMCP.Log).Write("info", "agent", "Agent run completed", logData)
    // The run may be performing in a background job: this is where the answer
    // reaches the invocation the caller is polling.
    If pInvocationId '= "" {
        Set respDyn = ##class(%Library.DynamicObject).%FromObject(response)
        Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "completed", respDyn, "", 0)
    }
    Set pResponse = response
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

/// Writes an operational event about the adapter's own work.
/// pStatus is the status of the operation the event reports, and may be
/// empty: an empty status means "nothing to report", not a failure.
ClassMethod WriteLog(pLevel As %String, pMessage As %String, pStatus As %Status, pData As %DynamicObject = "") As %Status
{
    If '$IsObject(pData) Set pData = ##class(%DynamicObject).%New()
    // An empty status is not an error: reporting one would put a failure
    // where the event describes a success.
    If (pStatus '= "") && ($$$ISERR(pStatus)) Do pData.%Set("status", $SYSTEM.Status.GetErrorText(pStatus))
    Do ##class(br.musketeers.InteropMCP.Log).Write(pLevel, "adapter", pMessage, pData)
    Quit $$$OK
}

/// Resolves the agent's configuration from the production that owns it.
/// Reads the settings of the item named pConfigName - the item this host
/// runs as - so that each host resolves the configuration of the item it
/// belongs to, and a revision of the document or of any other setting takes
/// effect on the next run without the production's components being
/// redeployed.
/// Outputs pSettings: a dynamic object carrying the settings, plus
/// "AdapterItem" (the name of the item the settings came from).
ClassMethod ResolveSettings(pProductionName As %String, pConfigName As %String, Output pSettings As %DynamicObject) As %Status
{
	Set sc = $$$OK
	Set pSettings = ##class(%DynamicObject).%New()
	Set prod = ##class(Ens.Config.Production).%OpenId(pProductionName)
	If '$IsObject(prod) {
		Quit $$$ERROR($$$GeneralError, "Production not found: "_pProductionName)
	}
	Set found = 0
	Set count = prod.Items.Count()
	For i = 1:1:count {
		Set item = prod.Items.GetAt(i)
		// The item is named by its config name in the production and by its
		// own name in the production's item list; both are accepted, so that
		// the caller does not have to know which one it holds.
		If ((prod.Name _ "." _ item.Name) = pConfigName) || (item.Name = pConfigName) {
			If item.Enabled {
				Set found = 1
				Do pSettings.%Set("AdapterItem", item.Name)
				Do pSettings.%Set("Prompt", ..Setting(item, "Prompt"))
				Do pSettings.%Set("Purpose", ..Setting(item, "Purpose"))
				Do pSettings.%Set("Model", ..Setting(item, "Model"))
				Do pSettings.%Set("ProviderConfig", ..Setting(item, "ProviderConfig"))
				Do pSettings.%Set("AgentTools", ..Setting(item, "AgentTools"))
				Do pSettings.%Set("MaxIterations", ..Setting(item, "MaxIterations"))
				Do pSettings.%Set("Timeout", ..Setting(item, "Timeout"))
				Do pSettings.%Set("KnowledgeBase", ..Setting(item, "KnowledgeBase"))
				Do pSettings.%Set("PolicyDocs", ..Setting(item, "PolicyDocs"))
				Do pSettings.%Set("ProductionConfig", ..Setting(item, "ProductionConfig"))
			}
		}
	}
	If 'found {
		Quit $$$ERROR($$$GeneralError, "No enabled item named "_pConfigName_" in production "_pProductionName)
	}
	Quit sc
}

/// Reads one of the adapter's settings from a production item. The adapter's
/// own settings live on the item's "Adapter" target; the item's own settings
/// are the host's, and the item carries no host settings of its own, so the
/// name identifies the setting unambiguously. Returns the empty string when
/// the setting is not defined.
ClassMethod Setting(pItem As Ens.Config.Item, pName As %String) As %String
{
	Set value = ""
	If pItem.GetModifiedSetting(pName, .value) {
		Quit value
	}
	Quit ""
}

/// Validates the agent's configuration the way an operator would read it:
/// each rejection names what is wrong and what to do about it, so that a
/// misconfigured agent is never published and never runs half-configured.
/// Outputs pReason: the reason the configuration was rejected, empty when the
/// configuration is usable.
ClassMethod Validate(pSettings As %DynamicObject, Output pReason As %String) As %Status
{
	Set pReason = ..ConfigProblem(pSettings)
	Set sc = $$$OK
	If pReason '= "" Set sc = $$$ERROR($$$GeneralError, pReason)
	Quit sc
}

/// Names the first problem with the agent's configuration, or the empty string
/// when the configuration is usable. The problems are the ones an operator can
/// act on: a missing document, a bound that bounds nothing, and a credential
/// written in the configuration instead of referenced from it.
ClassMethod ConfigProblem(pSettings As %DynamicObject) As %String
{
	// The agent needs a document. Without one it has no rules at all, and a
	// model given no rules will improvise them.
	Set prompt = pSettings.%Get("Prompt")
	If prompt = "" Quit "The agent has no document. Set the adapter's Prompt."

	// A bound that is not positive bounds nothing.
	Set maxIterations = pSettings.%Get("MaxIterations")
	If (maxIterations '= "") && (maxIterations <= 0) Quit "The effort bound is not usable. Set the adapter's MaxIterations to a positive number."
	Set timeout = pSettings.%Get("Timeout")
	If (timeout '= "") && (timeout <= 0) Quit "The time bound is not usable. Set the adapter's Timeout to a positive number of seconds."

	// The production's own parameters are carried as they are given: the
	// gateway does not interpret them, so the only thing it can check is
	// that they are well formed.
	Set productionConfig = pSettings.%Get("ProductionConfig")
	If productionConfig '= "" {
		Set reason = ..JsonProblem(productionConfig, "ProductionConfig")
		If reason '= "" Quit reason
	}

	// A credential is referenced, never written.
	Set providerConfig = pSettings.%Get("ProviderConfig")
	If providerConfig = "" Quit ""
	Set reason = ..CredentialProblem(providerConfig)
	Quit reason
}

/// Names the problem with a configuration that is meant to be a JSON object
/// but is not one, or the empty string when it is usable. The gateway
/// carries the production's parameters without interpreting them, so the
/// only thing it can check is that they are well formed.
ClassMethod JsonProblem(pConfig As %String, pName As %String) As %String
{
	Set json = ""
	Try {
		Set json = ##class(%DynamicObject).%FromJSON(pConfig)
	} Catch ex {
		Set json = ""
	}
	If $IsObject(json) {
		If json.%IsA("%DynamicObject") Quit ""
	}
	Quit "The " _ pName _ " is not a JSON object. Set the adapter's " _ pName _ " to a JSON object of the production's own parameters."
}

/// Names the problem with a provider configuration that carries a credential
/// value in it rather than a reference to the governed store, or the empty
/// string when the configuration carries no written credential. A credential
/// is referenced with a placeholder - an at-sign followed by an opening brace and
/// the reference itself, as the platform's settings syntax writes it.
ClassMethod CredentialProblem(pProviderConfig As %String) As %String
{
	Set reason = ""
	Set referencePrefix = $CHAR(64, 123)
	Set json = ""
	Try {
		Set json = ##class(%DynamicObject).%FromJSON(pProviderConfig)
	} Catch ex {
		// A configuration that is not JSON is not one a provider can be built
		// from; the builder reports that, and there is nothing to say here.
		Set json = ""
	}
	If $IsObject(json) {
		Set value = json.%Get("api_key")
		If value = "" Set value = json.%Get("apikey")
		If (value '= "") && ('$IsObject(value)) && ($Extract(value, 1, 2) '= referencePrefix) {
			Set reason = "The provider configuration carries a credential value. Reference the credential from the governed store or the environment instead of writing it in the configuration."
		}
	}
	Quit reason
}

}
