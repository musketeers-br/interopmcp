/// IRIS MCP Gateway - tool catalog builder.
/// Scans a running Interoperability production for Business Services annotated
/// for AI exposure (class parameters AIGATEWAY, AIGATEWAYDESC, AIGATEWAYASYNC,
/// AIGATEWAYWAIT, REQUESTCLASS) and publishes each one as an MCP tool.
/// Responsibilities:
/// - Build and cache the tool catalog (global ^InteropMCP.Catalog).
/// - Enforce unique tool names: a collision fails the build naming both
///   services, so an ambiguous catalog is never published.
/// - Generate and compile br.musketeers.InteropMCP.GeneratedTools (one typed method per
///   tool), keeping the published catalog in sync with the production
///   without manual code changes. The generated source is written to a
///   temporary artifact, not into the source-controlled tree.
/// The registry is production-agnostic: it operates on any production the
/// caller names and has no knowledge of the bundled demo production.
Class br.musketeers.InteropMCP.Registry Extends %RegisteredObject
{

/// Legacy filesystem root when the registry wrote generated output into the
/// source tree. GenerateToolsClass now writes to /tmp, so the parameter is
/// retained for compatibility and no longer used.
Parameter SourceRoot = "/home/irisowner/dev/src";

/// Default interactive wait window, in seconds, applied when a Business
/// Service does not override it through the AIGATEWAYWAIT annotation.
/// Executions expected to exceed this window should be flagged async
/// (AIGATEWAYASYNC) so agents receive a processing reference instead of
/// blocking the tool call.
Parameter WaitWindowSeconds = 30;

/// The class of the custom inbound adapter that carries an agent's
/// configuration. A production item of this class is published as an agent
/// rather than as a business capability.
Parameter AdapterClass = "br.musketeers.InteropMCP.Agent.Adapter";

/// Scans the enabled configuration items of pProduction, reads the AI
/// gateway annotations from each Business Service class and rebuilds the
/// published tool catalog. Afterwards generates and compiles
/// br.musketeers.InteropMCP.GeneratedTools so the new catalog becomes callable.
/// Idempotent: safe to run repeatedly. On duplicate tool names the build
/// fails with an error naming both services and nothing is published.
/// pProduction is the full production class name
/// (e.g. br.musketeers.InteropMCP.Demo.Production).
ClassMethod BuildCatalog(pProduction As %String) As %Status
{
    Set sc = $$$OK
    Kill ^InteropMCP.Catalog
    Set prod = ##class(Ens.Config.Production).%OpenId(pProduction)
    If '$IsObject(prod) Quit $$$ERROR($$$GeneralError, "Production not found: "_pProduction)
    Set agentScope = ""
    Set agentToolName = ""
    Set i = 1
    While 1 {
        Set item = ""
        Try {
            Set item = prod.Items.GetAt(i)
        } Catch ex {
            Set item = ""
        }
        If '$IsObject(item) Quit
        If item.Enabled {
            Set cd = ##class(%Dictionary.ClassDefinition).%OpenId(item.ClassName)
            If $IsObject(cd) {
                Set classification = $ZConvert(..GetParameter(cd, "AIGATEWAY"), "L")
                If classification '= "" {
                    If item.ClassName '= ..#AdapterClass {
                        Set toolName = item.Name
                        If $Length(toolName) > 2 {
                            If $ZConvert($Extract(toolName, *-1, *), "U") = "BS" Set toolName = $Extract(toolName, 1, *-2)
                        }
                        If $Data(^InteropMCP.Catalog(toolName)) {
                            Set existing = ##class(%DynamicObject).%FromJSON(^InteropMCP.Catalog(toolName))
                            Set sc = $$$ERROR($$$GeneralError, "Duplicate tool name "_toolName_" from "_existing.serviceName_" and "_item.ClassName)
                        } Else {
                            Set description = ..GetParameter(cd, "AIGATEWAYDESC")
                            Set requestClass = ..GetParameter(cd, "REQUESTCLASS")
                            If requestClass = "" Set requestClass = $Extract(item.ClassName, 1, *-2) _ "Request"
                            Set isAsync = (..GetParameter(cd, "AIGATEWAYASYNC") = "1")
                            Set waitVal = ..GetParameter(cd, "AIGATEWAYWAIT")
                            If waitVal = "" Set waitVal = ..#WaitWindowSeconds
                            Set def = ##class(%DynamicObject).%New()
                            Do def.%Set("kind", "capability")
                            Do def.%Set("classification", classification)
                            Do def.%Set("description", description)
                            Do def.%Set("serviceName", item.Name)
                            Do def.%Set("serviceClass", item.ClassName)
                            Do def.%Set("requestClass", requestClass)
                            Do def.%Set("async", isAsync)
                            Do def.%Set("wait", waitVal)
                            Do def.%Set("enabled", 1)
                            Set ^InteropMCP.Catalog(toolName) = def.%ToJSON()
                        }
                    }
                }
            }
        }
        Set i = i + 1
    }

    // The agent's entry is not a business capability: it is published from
    // the production item whose adapter is the agent's own inbound adapter.
    Set sc = ..BuildAgentEntry(prod, .agentToolName)
    If $$$ISERR(sc) Quit sc
    Set agentScope = ..AgentScope(prod)

    // Register meta tools not backed by a production Business Service
    // These are published directly in the catalog (not generated by BuildCatalog)
    Set metaDef = ##class(%DynamicObject).%New()
    Do metaDef.%Set("kind", "meta")
    Do metaDef.%Set("classification", "write")
    Do metaDef.%Set("description", "Request human-approval workflow for any tool execution")
    Do metaDef.%Set("serviceName", "CreateWorkflowTask")
    Do metaDef.%Set("serviceClass", "br.musketeers.InteropMCP.MetaTools")
    Do metaDef.%Set("requestClass", "")
    Do metaDef.%Set("async", 0)
    Do metaDef.%Set("wait", ..#WaitWindowSeconds)
    Do metaDef.%Set("enabled", 1)
    Set ^InteropMCP.Catalog("CreateWorkflowTask") = metaDef.%ToJSON()

    If $$$ISERR(sc) Quit sc
    Set sc = ..GenerateToolsClass()
    If $$$ISERR(sc) Quit sc
    Set sc = ..GenerateAgentToolsClass(agentScope, agentToolName)
    If $$$ISERR(sc) Quit sc
    If ##class(%Dictionary.ClassDefinition).%ExistsId("br.musketeers.InteropMCP.ToolSet") {
        Set sc = $SYSTEM.OBJ.Compile("br.musketeers.InteropMCP.ToolSet", "ck")
        If $$$ISERR(sc) Quit sc
    }
    If ##class(%Dictionary.ClassDefinition).%ExistsId("br.musketeers.InteropMCP.Agent.ToolSet") {
        Set sc = $SYSTEM.OBJ.Compile("br.musketeers.InteropMCP.Agent.ToolSet", "ck")
        If $$$ISERR(sc) Quit sc
    }
    Set ^InteropMCP.CatalogVersion = $Get(^InteropMCP.CatalogVersion) + 1
    Quit sc
}

/// Builds the catalogue entry of an agent adapter item and publishes it.
/// The published name follows the gateway's naming convention: the item's
/// name without a trailing "Adapter", the same way a business service loses
/// its trailing "BS". The entry points at the business host that runs the
/// agent, so that the existing invoker reaches it the way it reaches every
/// other business service.
/// Outputs pToolName: the published name of the agent, empty when the
/// production has no enabled agent adapter.
ClassMethod BuildAgentEntry(pProd As Ens.Config.Production, Output pToolName As %String) As %Status
{
    Set pToolName = ""
    Set sc = $$$OK
    Set item = ""
    Set count = pProd.Items.Count()
    For i = 1:1:count {
        Set candidate = pProd.Items.GetAt(i)
        If (candidate.AdapterClassName() = ..#AdapterClass) {
            If candidate.Enabled {
                Set item = candidate
            }
        }
    }
    If '$IsObject(item) Quit sc

    // A misconfigured agent is not published at all: the gateway does not
    // offer a capability it cannot serve, and the operator is told why
    // instead of discovering it at the first call.
    Set settings = ""
    Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).ResolveSettings(pProd.Name, .settings)
    If $$$ISERR(sc) {
        Set sc = $$$OK
    } Else {
        Set reason = ""
        Set sc = ##class(br.musketeers.InteropMCP.Agent.Adapter).Validate(settings, .reason)
        If $$$ISERR(sc) {
            Set data = ##class(%DynamicObject).%New()
            Do data.%Set("item", item.Name)
            Do data.%Set("reason", reason)
            Do ##class(br.musketeers.InteropMCP.Log).Write("warning", "registry", "The agent was not published: its configuration is not usable.", data)
            Quit $$$OK
        }
    }

    // The published name drops a trailing "Adapter", the same way a business
    // service drops its trailing "BS". A negative position counts from the
    // end: *-1 is the last character, so a suffix of L characters starts at
    // *-(L-1).
    Set toolName = item.Name
    If $Length(toolName) > 7 {
        If $ZConvert($Extract(toolName, *-6, *), "U") = "ADAPTER" Set toolName = $Extract(toolName, 1, *-7)
    }
    If toolName = "" Set toolName = item.Name

    If $Data(^InteropMCP.Catalog(toolName)) {
        Set existing = ##class(%DynamicObject).%FromJSON(^InteropMCP.Catalog(toolName))
        Set sc = $$$ERROR($$$GeneralError, "Duplicate tool name "_toolName_" from "_existing.serviceName_" and "_item.ClassName)
        Quit sc
    }

    Set classification = "write"
    Set cd = ##class(%Dictionary.ClassDefinition).%OpenId(..#AdapterClass)
    If $IsObject(cd) {
        Set value = $ZConvert(..GetParameter(cd, "AIGATEWAY"), "L")
        If value '= "" Set classification = value
    }

    Set def = ##class(%DynamicObject).%New()
    Do def.%Set("kind", "agent")
    Do def.%Set("classification", classification)
    Do def.%Set("description", ..AdapterSetting(item, "Purpose"))
    Do def.%Set("serviceName", item.Name)
    Do def.%Set("serviceClass", "br.musketeers.InteropMCP.Agent.Host")
    Do def.%Set("requestClass", "br.musketeers.InteropMCP.Agent.Request")
    // An agent run outlasts the response window of the transport that carries
    // it, so it is dispatched asynchronously: the caller gets a processing
    // reference and the answer is collected from the invocation.
    Do def.%Set("async", 1)
    Do def.%Set("wait", 30)
    Do def.%Set("enabled", 1)
    Set ^InteropMCP.Catalog(toolName) = def.%ToJSON()
    Set pToolName = toolName
    Quit sc
}

/// The reachable capability scope the adapter allows: the AgentTools setting
/// of the agent's adapter. Empty means every published capability.
ClassMethod AgentScope(pProd As Ens.Config.Production) As %String
{
    Set scope = ""
    Set count = pProd.Items.Count()
    For i = 1:1:count {
        Set item = pProd.Items.GetAt(i)
        If (item.AdapterClassName() = ..#AdapterClass) {
            If item.Enabled {
                Set scope = ..AdapterSetting(item, "AgentTools")
            }
        }
    }
    Quit scope
}

/// Reads one of the agent adapter's settings from a production item. The
/// adapter's own settings live on the item's "Adapter" target; the item's
/// own settings are the host's, and the item carries no host settings of its
/// own, so the name identifies the setting unambiguously.
ClassMethod AdapterSetting(pItem As Ens.Config.Item, pName As %String) As %String
{
    Set value = ""
    If pItem.GetModifiedSetting(pName, .value) {
        Quit value
    }
    Quit ""
}

/// Reads a single class parameter value from an opened
/// %Dictionary.ClassDefinition. The dictionary stores parameter defaults in
/// the Default property (not Value). Returns the empty string when the
/// parameter is absent.
ClassMethod GetParameter(cd As %Dictionary.ClassDefinition, pName As %String) As %String
{
    Set result = ""
    For j = 1:1:cd.Parameters.Count() {
        Set p = cd.Parameters.GetAt(j)
        If p.Name = pName Set result = p.Default
    }
    Quit result
}

/// Emits the br.musketeers.InteropMCP.GeneratedTools class source from the published
/// catalog and compiles it: one ClassMethod per enabled tool, with typed
/// parameters mapped from the request class schema, each delegating to
/// Guardrails.Check and then Invoker.Invoke. The fixed status polling tool
/// is provided separately by br.musketeers.InteropMCP.InvocationStatusTools and is not
/// generated here. Called by BuildCatalog; the output file is written to a
/// temporary path and compiled, so it is never edited by hand.
ClassMethod GenerateToolsClass() As %Status
{
    Set q = $CHAR(34)
    Set path = "/tmp/InteropMCP.GeneratedTools.cls"
    Set io = $IO
    Open path:"WNS":0
    If $Test = 0 Quit $$$ERROR($$$GeneralError, "Cannot open generated tools file: "_path)
    Use path
    Write "/// Code-generated by br.musketeers.InteropMCP.Registry.BuildCatalog.",!
    Write "/// Do not edit manually: this file is regenerated on every catalog build.",!
    Write "Class br.musketeers.InteropMCP.GeneratedTools Extends %AI.Tool",!
    Write "{",!
    Set name = ""
    For {
        Set name = $Order(^InteropMCP.Catalog(name))
        If name = "" Quit
        Set raw = ^InteropMCP.Catalog(name)
        Set def = ##class(%DynamicObject).%FromJSON(raw)
        If 'def.enabled Continue
        Do ..WriteToolMethod(name, def)
    }
    Write "}",!
    Close path
    Use io
    Set sc = $$$OK
    Set sc = $SYSTEM.OBJ.Load(path, "ck")
    Quit sc
}

/// Emits the br.musketeers.InteropMCP.AgentTools class source and compiles
/// it: the capabilities the agent may reach, with the same bodies the
/// published tools have, so that the classification, the approval gate, and
/// the invocation record apply to the agent's actions exactly as they apply
/// to a direct caller's. The agent's own entry is never part of this surface,
/// so the agent cannot call itself.
/// pScope is the comma-separated list of capabilities the adapter allows;
/// the empty list means every published capability. pExclude is the published
/// name of the agent, which is kept out of the agent's own surface.
ClassMethod GenerateAgentToolsClass(pScope As %String, pExclude As %String) As %Status
{
    Set q = $CHAR(34)
    Set path = "/tmp/InteropMCP.AgentTools.cls"
    Set io = $IO
    Open path:"WNS":0
    If $Test = 0 Quit $$$ERROR($$$GeneralError, "Cannot open generated agent tools file: "_path)
    Use path
    Write "/// Code-generated by br.musketeers.InteropMCP.Registry.BuildCatalog.",!
    Write "/// Do not edit manually: this file is regenerated on every catalog build.",!
    Write "Class br.musketeers.InteropMCP.AgentTools Extends %AI.Tool",!
    Write "{",!
    Set scope = ..ParseScope(pScope)
    Set name = ""
    For {
        Set name = $Order(^InteropMCP.Catalog(name))
        If name = "" Quit
        If name = pExclude Continue
        Set raw = ^InteropMCP.Catalog(name)
        Set def = ##class(%DynamicObject).%FromJSON(raw)
        If 'def.enabled Continue
        Set kind = def.kind
        If kind = "" Set kind = "capability"
        If kind = "capability" {
            If (scope '= "") && '..InScope(name, scope) Continue
        }
        Do ..WriteToolMethod(name, def)
    }
    Write "}",!
    Close path
    Use io
    Set sc = $$$OK
    Set sc = $SYSTEM.OBJ.Load(path, "ck")
    Quit sc
}

/// Writes the source of one generated tool method: the docstring that
/// becomes the tool's published description, the typed parameters mapped from
/// the request class schema, and the body that delegates to Guardrails.Check
/// and then Invoker.Invoke. Writes nothing when the entry carries no request
/// class or its schema cannot be mapped.
ClassMethod WriteToolMethod(pName As %String, pDef As %DynamicObject) As %Status
{
    Set q = $CHAR(34)
    Set requestClass = pDef.requestClass
    If requestClass = "" Quit $$$OK
    Set mapping = ##class(br.musketeers.InteropMCP.SchemaMapper).MapProperties(requestClass, .mapSc)
    If $$$ISERR(mapSc) Quit $$$OK
    Set props = mapping.%Get("properties")
    Set args = ""
    Set first = 1
    Set iter = props.%GetIterator()
    While iter.%GetNext(.pidx, .pdef) {
        Set pname = pdef.name
        If 'first Set args = args _ ", "
        Set first = 0
        Set argType = ..ToArgType(pdef.type)
        Set args = args _ pname _ " As " _ argType
        If 'pdef.required Set args = args _ " = "_q_q
    }
    Set description = pDef.description
    If description = "" {
        Write "  /// ", pName, ".", !
    } Else {
        Set lines = ..SplitLines(description)
        For i = 1:1:$ListLength(lines) {
            Set line = $List(lines, i)
            If line = "" {
                Write "  ///", !
            } Else {
                Write "  /// ", line, !
            }
        }
    }
    Write "  ClassMethod "_pName_"("_args_") As %DynamicObject",!
    Write "  {",!
    Write "    Set result = ##class(%DynamicObject).%New()",!
    Write "    Set params = ##class(%DynamicObject).%New()",!
    Set iter = props.%GetIterator()
    While iter.%GetNext(.pidx, .pdef) {
        Set pname = pdef.name
        Write "    Do params.%Set("_q_pname_q_", "_pname_")",!
    }
    Write "    Set proceed = 0",!
    Write "    Set holdId = "_q_q,!
    Write "    Set invId = "_q_q,!
    Write "    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("_q_pName_q_", params, ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent(), .proceed, .holdId, .invId, .gsc)",!
    Write "    If $$$ISERR(gsc) {",!
    Write "      Do result.%Set(""_status"", ""error"")",!
    Write "      Do result.%Set(""message"", ""Guardrail error"")",!
    Write "      Quit result",!
    Write "    }",!
    Write "    If 'proceed {",!
    Write "      Do result.%Set(""_status"", ""held"")",!
    Write "      Do result.%Set(""invocationId"", invId)",!
    Write "      Do result.%Set(""approvalId"", holdId)",!
    Write "      Do result.%Set(""message"", ""Critical call held for approval. Use GetInvocationStatus with invocationId to check progress."")",!
    Write "      Quit result",!
    Write "    }",!
    Write "    Set sc = ##class(br.musketeers.InteropMCP.Invoker).Invoke("_q_pName_q_", params, ##class(br.musketeers.InteropMCP.Guardrails).CurrentAgent(), .invId, .resp)",!
    Write "    If $$$ISERR(sc) {",!
    Write "      Do result.%Set(""_status"", ""error"")",!
    Write "      Do result.%Set(""invocationId"", invId)",!
    Write "      Do result.%Set(""message"", ""The tool did not complete. Use GetInvocationStatus with invocationId for the reason."")",!
    Write "      Quit result",!
    Write "    }",!
    If pDef.async {
        Write "    Do result.%Set(""_status"", ""pending"")",!
        Write "    Do result.%Set(""invocationId"", invId)",!
        Write "    Do result.%Set(""message"", ""The run has started. Use GetInvocationStatus with invocationId to collect the result."")",!
    } Else {
        Write "    Do result.%Set(""_status"", ""ok"")",!
        Write "    Do result.%Set(""invocationId"", invId)",!
        Write "    Do result.%Set(""message"", ""Tool executed successfully."")",!
    }
    Write "    Quit result",!
    Write "  }",!
    Write "",!
    Quit $$$OK
}

/// Splits a text into its lines, on either line ending.
ClassMethod SplitLines(pText As %String) As %String
{
    Set normalized = $Replace($Replace(pText, $C(13, 10), $C(10)), $C(13), $C(10))
    Set lines = ""
    If normalized = "" {
        Set lines = $lb("")
        Quit lines
    }
    // The lines are taken by position instead of by scanning for the
    // separator: the position $FIND reports is not the separator's own
    // position, and a scan drops the first character of every line but the
    // first.
    Set count = $L(normalized, $C(10))
    For i = 1:1:count {
        Set lines = lines _ $lb($P(normalized, $C(10), i))
    }
    Quit lines
}

/// Splits a comma-separated list of capability names into a list.
ClassMethod ParseScope(pScope As %String) As %String
{
    Set scope = ""
    If pScope = "" Quit scope
    // The names are taken by position instead of by scanning for the comma:
    // the position $FIND reports is not the comma's own position, and a scan
    // drops the first character of every name but the first.
    Set count = $L(pScope, ",")
    For i = 1:1:count {
        Set part = $Replace($P(pScope, ",", i), " ", "")
        If part '= "" Set scope = scope _ $lb(part)
    }
    Quit scope
}

/// Whether a published tool's name is in the scope list.
ClassMethod InScope(pName As %String, pScope As %String) As %Boolean
{
    // The match is collected in a flag instead of returning from inside the
    // loop: a QUIT that carries a value is not allowed inside a FOR block.
    Set found = 0
    Set count = $ListLength(pScope)
    For i = 1:1:count {
        If $List(pScope, i) = pName Set found = 1
    }
    Quit found
}

/// Maps a schema type token (from SchemaMapper) to an ObjectScript method
/// argument type used in the generated tool signatures. Unknown types fall
/// back to %String.
ClassMethod ToArgType(pType As %String) As %String
{
    If pType = "string" Quit "%String"
    If pType = "integer" Quit "%Integer"
    If pType = "number" Quit "%Numeric"
    If pType = "boolean" Quit "%Boolean"
    Quit "%String"
}

/// Returns the currently published catalog: a dynamic object with a tools
/// array, where each entry carries name, classification, description,
/// serviceName, serviceClass, requestClass, async, wait and enabled.
ClassMethod ListTools(Output pTools As %DynamicObject) As %Status
{
    Set tools = ##class(%DynamicArray).%New()
    Set name = ""
    For {
        Set name = $Order(^InteropMCP.Catalog(name))
        If name = "" Quit
        Set def = ##class(%DynamicObject).%FromJSON(^InteropMCP.Catalog(name))
        Do def.%Set("name", name)
        Do tools.%Push(def)
    }
    Set pTools = ##class(%DynamicObject).%New()
    Do pTools.%Set("tools", tools)
    Quit $$$OK
}

/// Returns the published definition of one tool. Fails when the tool is not
/// in the catalog (agent-facing error path for unknown tool names).
ClassMethod GetToolDefinition(pTool As %String, Output pDef As %DynamicObject) As %Status
{
    Set raw = $Get(^InteropMCP.Catalog(pTool))
    If raw = "" Quit $$$ERROR($$$GeneralError, "Tool not found: "_pTool)
    Set pDef = ##class(%DynamicObject).%FromJSON(raw)
    Quit $$$OK
}

/// Enables or disables a tool in the published catalog. Disabled tools
/// disappear from tools/list and their invocations are refused, without
/// requiring a catalog rebuild.
ClassMethod SetEnabled(pTool As %String, pEnabled As %Boolean) As %Status
{
    Set raw = $Get(^InteropMCP.Catalog(pTool))
    If raw = "" Quit $$$ERROR($$$GeneralError, "Tool not found: "_pTool)
    Set def = ##class(%DynamicObject).%FromJSON(raw)
    Do def.%Set("enabled", pEnabled)
    Set ^InteropMCP.Catalog(pTool) = def.%ToJSON()
    Quit $$$OK
}

/// Returns the gateway runtime configuration (waitWindowSeconds).
ClassMethod GetConfig() As %DynamicObject
{
    Set config = ##class(%DynamicObject).%New()
    Do config.%Set("waitWindowSeconds", ..#WaitWindowSeconds)
    Quit config
}

/// Returns the active production name in the current namespace.
/// Falls back to ^InteropMCP.Config("production") if set.
/// Returns empty string if no production is active and no config is set.
ClassMethod GetActiveProduction() As %String
{
    Set prod = ""
    // Override via config if set
    Set prod = $Get(^InteropMCP.Config("production"))
    If prod '= "" Quit prod
    // Try runtime active production
    Set prod = $Get(^Ens.Runtime("Name"))
    Quit prod
}

/// Builds catalog for the active production or configured default.
/// Resilient: returns error if no production is available.
ClassMethod BuildCatalogForActive() As %Status
{
    Set prod = ..GetActiveProduction()
    If prod = "" Quit $$$ERROR($$$GeneralError, "No active production found and no ^InteropMCP.Config production override set")
    Quit ..BuildCatalog(prod)
}

/// Sets default production override in ^InteropMCP.Config.
ClassMethod SetDefaultProduction(pProduction As %String) As %Status
{
    Set ^InteropMCP.Config("production") = pProduction
    Quit $$$OK
}


}
