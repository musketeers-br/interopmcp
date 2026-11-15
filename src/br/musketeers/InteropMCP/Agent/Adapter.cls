/// IRIS MCP Gateway - the custom inbound adapter that gives a production an agent.
/// This is the component an operator attaches to a production that already
/// works, and the component they configure. It owns the agent's
/// configuration - the document that dictates the agent's rules, the model,
/// the capabilities the agent may reach, the bounds of a run, and the
/// knowledge it retrieves.
/// Responsibilities:
/// - Hold the agent's configuration as adapter settings an operator sets on
///   the production item, so that the configuration lives in the production
///   and is changed in one place.
/// - Resolve that configuration at run time, so that a revision takes effect
///   on the next run without the production's components being redeployed.
/// - Receive the goals an external trigger delivers, which are handed to the
///   business host that runs the agent.
/// The adapter is referenced by the business host's ADAPTER parameter: a
/// production item is a business host, and the framework creates the adapter
/// for it. The agent runs inside the production, in that host. The MCP path
/// does not come through this adapter: the gateway calls the host directly,
/// which is why an inbound adapter cannot serve as the gateway's entry point.
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

/// The settings an operator sets on the production item.
Parameter SETTINGS = "Prompt:Basic,Purpose:Basic,Model:Basic,ProviderConfig:Basic,AgentTools:Basic,MaxIterations:Basic,Timeout:Basic,KnowledgeBase:Basic,PolicyDocs:Basic,ProductionConfig:Basic";

/// The agent does not poll for work: the gateway calls the agent's business
/// host directly. A production that wants to accept goals from an external
/// trigger overrides this method and forwards what it received to the
/// business host.
Method OnTask() As %Status
{
	Quit $$$OK
}

/// Resolves the agent's configuration from the production that owns it.
/// Reads the adapter settings of the enabled item whose adapter is this
/// class, so that a revision of the document or of any other setting takes
/// effect on the next run without the production's components being redeployed.
/// Outputs pSettings: a dynamic object carrying the settings, plus
/// "AdapterItem" (the name of the item the settings came from).
ClassMethod ResolveSettings(pProductionName As %String, Output pSettings As %DynamicObject) As %Status
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
		If (item.AdapterClassName() = ..#AdapterClass) {
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
		Quit $$$ERROR($$$GeneralError, "No enabled agent adapter found in production "_pProductionName)
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
/// string when the configuration carries no written credential. A credential is
/// referenced with a placeholder - an at-sign followed by an opening brace and
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
