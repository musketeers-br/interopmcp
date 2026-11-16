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

/// Runs one queued item: restores the context that produced it, hands it to
/// the business host that runs the agent, and records the outcome on the
/// queue.
Method Run(pEntry As %DynamicObject, pQueueId As %String) As %Status
{
    Set sc = $$$OK
    Set goal = pEntry.%Get("goal")
    Set invocationId = pEntry.%Get("invocationId")
    Set agentIdentity = pEntry.%Get("agentIdentity")
    Set source = pEntry.%Get("source")
    Set sessionId = pEntry.%Get("sessionId")

    // The caller's identity and the session live in process-private globals
    // and do not cross the boundary between the job that produced the work
    // and the job that consumes it. The context travels with the work and is
    // restored here, so that the agent's own calls are attributed to the
    // caller that started the run, and the run's trace belongs to it.
    If agentIdentity '= "" Set ^||InteropMCP.AgentIdentity = agentIdentity
    If source '= "" Set ^||InteropMCP.Source = source
    // Each run belongs to its own session: the polling job is long-lived, so
    // the session is cleared rather than inherited from the previous run.
    If sessionId '= "" {
        Set ^||InteropMCP.SessionId = sessionId
    } Else {
        Kill ^||InteropMCP.SessionId
    }

    Set request = ##class(br.musketeers.InteropMCP.Agent.Request).%New()
    Set request.Goal = goal
    Set request.GatewayInvocationId = invocationId

    Set response = ""
    Try {
        Set sc = ..BusinessHost.ProcessInput(request, .response)
    } Catch ex {
        Set sc = ex.AsStatus()
    }

    If $$$ISERR(sc) {
        Set reason = $SYSTEM.Status.GetErrorText(sc)
        // The host records the reason in the response before it raises the
        // failure, so the queue carries the reason and not just a status.
        If $IsObject(response) {
            Try {
                Set answer = response.Answer
                If answer '= "" Set reason = answer
            } Catch ex {
                Set tIgnored = 1
            }
        }
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

/// Writes an operational event about the adapter's own work.
Method WriteLog(pLevel As %String, pMessage As %String, pStatus As %Status, pData As %DynamicObject = "") As %Status
{
    If '$IsObject(pData) Set pData = ##class(%DynamicObject).%New()
    If $$$ISERR(pStatus) Do pData.%Set("status", $SYSTEM.Status.GetErrorText(pStatus))
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
