/// IRIS MCP Gateway - assembles the agent from the adapter's configuration.
/// Builds the %AI.Agent the adapter's settings describe: the model, the
/// provider, the document that dictates the agent's rules, the tool surface
/// the agent may reach, and the effort bound for a run.
/// Responsibilities:
/// - Create the provider from the adapter's provider configuration, resolving
///   any credential reference through the platform's governed settings, so
///   that no credential is ever written in the adapter's configuration.
/// - Give the agent the tool surface of the production, which is the set of
///   published capabilities it may reach. The agent's own entry is not part of
///   that surface, so the agent cannot call itself.
/// - Apply the effort bound, so that a run cannot iterate without end.
Class br.musketeers.InteropMCP.Agent.Builder Extends %RegisteredObject
{

/// The tool set the agent is given: the production's published capabilities,
/// scoped to what the adapter allows.
Parameter ToolSetClass = "br.musketeers.InteropMCP.Agent.ToolSet";

/// The effort bound applied when the operator did not set one.
Parameter DefaultMaxIterations = 20;

/// The time bound applied when the operator did not set one, in seconds.
/// The policy documents in the prompt make a run slower than the old 120s
/// default; keep enough headroom for the model to finish a PDF assessment.
Parameter DefaultTimeout = 240;

/// Builds the agent described by pSettings.
/// Outputs pAgent: the agent, ready to create a session and run.
/// Outputs pSessionConfig: the configuration the session is created with,
/// carrying the run's time bound.
ClassMethod Build(pSettings As %DynamicObject, Output pAgent As %AI.Agent, Output pSessionConfig As %DynamicObject) As %Status
{
	Set sc = $$$OK
	Set agent = ##class(%AI.Agent).%New()

	Set prompt = pSettings.%Get("Prompt")
	If prompt = "" {
		Quit $$$ERROR($$$GeneralError, "The agent has no document. Set the adapter's Prompt.")
	}
	Set agent.SystemPrompt = prompt

	Set model = pSettings.%Get("Model")
	If model '= "" Set agent.Model = model

	Set maxIterations = pSettings.%Get("MaxIterations")
	If maxIterations <= 0 Set maxIterations = ..#DefaultMaxIterations
	Set agent.MaxIterations = maxIterations

	// The time bound is applied to the session's configuration, which is
	// where the platform reads it: the session's wall-clock budget is the
	// bound on the whole agentic loop. Without it a run is bounded only by
	// the effort bound, and the time bound an operator set bounds nothing.
	Set timeout = pSettings.%Get("Timeout")
	If timeout <= 0 Set timeout = ..#DefaultTimeout
	Set sessionConfig = {}
	Do sessionConfig.%Set("timeout_ms", timeout * 1000, "number")

	Set agent.ToolSets = ..#ToolSetClass

	Set sc = ..BuildProvider(pSettings, .provider)
	If $$$ISERR(sc) Quit sc
	Set agent.Provider = provider

	// The operator may point the agent at the policy documents that govern its
	// work. They are instructions, not retrieved passages: loading them into the
	// system prompt keeps the agent's reasoning grounded without introducing a
	// vector store and an embedding provider into every run.
	Set policyDocs = pSettings.%Get("PolicyDocs")
	If policyDocs '= "" {
		Set sc = ..AppendPolicyDocs(policyDocs, .docs)
		If $$$ISERR(sc) Quit sc
		If docs '= "" Set agent.SystemPrompt = agent.SystemPrompt _ $C(10, 10) _ docs
	}

	// The production's own parameters are part of the agent's instructions: this
	// is where a production names the files and the records its rules refer to.
	// The gateway carries them and does not interpret them - the keys belong to
	// the production - so they are handed over as they were given.
	Set productionConfig = pSettings.%Get("ProductionConfig")
	If productionConfig '= "" {
		Set agent.SystemPrompt = agent.SystemPrompt _ $C(10, 10) _ "# Production configuration" _ $C(10) _ productionConfig
	}

	// The tool set is only a declaration until the agent initialises: %Init
	// loads the instructions, discovers the tools and prepares the manager.
	// Without it the agent runs with an empty tool manager and improvises the
	// capabilities it was supposed to call.
	Set sc = agent.%Init()
	If $$$ISERR(sc) Quit sc

	// The session configuration travels with the agent, so the host creates
	// the session with the bound applied.
	Set pAgent = agent
	Set pSessionConfig = sessionConfig
	Quit sc
}

/// Reads the policy documents named by pPath into pText. pPath is either a
/// directory, in which case every .md file is read in name order, or a
/// comma-separated list of files. A configured path that yields no documents is
/// a configuration error: it is better to refuse the run than to let the agent
/// reason without the rules the operator meant to give it.
ClassMethod AppendPolicyDocs(pPath As %String, Output pText As %String) As %Status
{
	Set pText = ""
	Set count = 0
	Set sc = $$$OK
	If ##class(%File).DirectoryExists(pPath) {
		Set dir = ##class(%File).NormalizeDirectory(pPath)
		Set rs = ##class(%ResultSet).%New("%File:FileSet")
		Set sc = rs.Execute(dir, "*.md")
		If $$$ISERR(sc) Quit sc
		While rs.Next(.sc) {
			If $$$ISERR(sc) Quit
			If rs.Get("Type") = "F" {
				Set count = count + 1
				Set files(count) = rs.Get("Name")
			}
		}
		If $$$ISERR(sc) Quit sc
	} Else {
		For i = 1:1:$Length(pPath, ",") {
			Set one = $ZStrip($Piece(pPath, ",", i), "<>W")
			If one '= "" {
				Set count = count + 1
				Set files(count) = one
			}
		}
	}
	If count = 0 Quit $$$ERROR($$$GeneralError, "No policy documents found at "_pPath)

	Set text = ""
	Set i = ""
	For {
		Set i = $Order(files(i))
		If i = "" Quit
		Set fileName = files(i)
		Set stream = ##class(%Stream.FileCharacter).%New()
		Set stream.TranslateTable = "UTF8"
		Set sc = stream.LinkToFile(fileName)
		If $$$ISERR(sc) Quit
		Do stream.Rewind()
		Set body = stream.Read(100000)
		Do stream.%Close()
		Set text = text _ $C(10, 10) _ "# " _ ##class(%File).GetFilename(fileName) _ $C(10) _ body
	}
	If $$$ISERR(sc) Quit sc
	Set pText = text
	Quit $$$OK
}

/// Resolves the model provider from the adapter's provider configuration.
/// The configuration is JSON; any @{prefix:key} placeholder inside it is
/// resolved by the platform's settings, which is how a credential is
/// referenced rather than stored. The configuration must name a provider.
ClassMethod BuildProvider(pSettings As %DynamicObject, Output pProvider As %AI.Provider) As %Status
{
	Set sc = $$$OK
	Set providerConfig = pSettings.%Get("ProviderConfig")
	If providerConfig = "" {
		Quit $$$ERROR($$$GeneralError, "No model provider configured for the agent. Set the adapter's ProviderConfig.")
	}
	Set providerSettings = ""
	Try {
		Do ##class(%AI.Utils.SettingStore).RegisterDefaults()
		Set expanded = ##class(%AI.Utils.SettingStore).Expand(providerConfig)
		Set providerSettings = {}.%FromJSON(expanded)
	} Catch ex {
		Set sc = $$$ERROR($$$GeneralError, "The agent's provider configuration could not be resolved: "_ex.DisplayString())
	}
	If $$$ISERR(sc) Quit sc
	Set providerName = providerSettings.%Get("model_provider")
	If providerName = "" {
		Quit $$$ERROR($$$GeneralError, "The agent's provider configuration does not name a provider (model_provider).")
	}
	Try {
		Set pProvider = ##class(%AI.Provider).Create(providerName, providerSettings)
	} Catch ex {
		Set sc = $$$ERROR($$$GeneralError, "The agent's model provider could not be created: "_ex.DisplayString())
	}
	If $$$ISERR(sc) Quit sc
	If '$IsObject(pProvider) {
		Quit $$$ERROR($$$GeneralError, "The agent's model provider could not be created: "_providerName)
	}
	Quit sc
}

}
