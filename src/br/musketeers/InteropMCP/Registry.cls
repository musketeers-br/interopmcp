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
///   without manual code changes.
/// The registry is production-agnostic: it operates on any production the
/// caller names and has no knowledge of the bundled demo production.
Class br.musketeers.InteropMCP.Registry Extends %RegisteredObject
{

/// Filesystem root that holds the gateway sources. GenerateToolsClass writes
/// the generated tools class to SourceRoot/br/musketeers/InteropMCP/GeneratedTools.cls and
/// compiles it. The default matches the container layout
/// (/home/irisowner/dev/src).
Parameter SourceRoot = "/home/irisowner/dev/src";

/// Default interactive wait window, in seconds, applied when a Business
/// Service does not override it through the AIGATEWAYWAIT annotation.
/// Executions expected to exceed this window should be flagged async
/// (AIGATEWAYASYNC) so agents receive a processing reference instead of
/// blocking the tool call.
Parameter WaitWindowSeconds = 30;

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
        Set i = i + 1
    }
    If $$$ISERR(sc) Quit sc
    Set sc = ..GenerateToolsClass()
    Quit sc
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
/// generated here. Called by BuildCatalog; the output file is written under
/// SourceRoot and must not be edited by hand.
ClassMethod GenerateToolsClass() As %Status
{
    Set q = $CHAR(34)
    Set path = ..#SourceRoot _ "/br/musketeers/InteropMCP/GeneratedTools.cls"
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(path)
    Do stream.WriteLine("/// Code-generated by br.musketeers.InteropMCP.Registry.BuildCatalog.")
    Do stream.WriteLine("/// Do not edit manually: this file is regenerated on every catalog build.")
    Do stream.WriteLine("Class br.musketeers.InteropMCP.GeneratedTools Extends %AI.Tool")
    Do stream.WriteLine("{")
    Set name = ""
    For {
        Set name = $Order(^InteropMCP.Catalog(name))
        If name = "" Quit
        Set raw = ^InteropMCP.Catalog(name)
        Set def = ##class(%DynamicObject).%FromJSON(raw)
        If 'def.enabled Continue
        Set mapping = ##class(br.musketeers.InteropMCP.SchemaMapper).MapProperties(def.requestClass, .mapSc)
        If $$$ISERR(mapSc) Continue
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
        Do stream.WriteLine("  ClassMethod "_name_"("_args_") As %Status")
        Do stream.WriteLine("  {")
        Do stream.WriteLine("    Set params = ##class(%DynamicObject).%New()")
        Set iter = props.%GetIterator()
        While iter.%GetNext(.pidx, .pdef) {
            Set pname = pdef.name
            Do stream.WriteLine("    Do params.%Set("_q_pname_q_", "_pname_")")
        }
        Do stream.WriteLine("    Set proceed = 0")
        Do stream.WriteLine("    Set holdId = "_q_q)
        Do stream.WriteLine("    Set sc = ##class(br.musketeers.InteropMCP.Guardrails).Check("_q_name_q_", params, "_q_"agent"_q_", .proceed, .holdId, .gsc)")
        Do stream.WriteLine("    If $$$ISERR(gsc) Quit gsc")
        Do stream.WriteLine("    If 'proceed Quit $$$OK")
        Do stream.WriteLine("    Set sc = ##class(br.musketeers.InteropMCP.Invoker).Invoke("_q_name_q_", params, "_q_"agent"_q_", .invId, .resp)")
        Do stream.WriteLine("    Quit sc")
        Do stream.WriteLine("  }")
        Do stream.WriteLine("")
    }
    Do stream.WriteLine("}")
    Do stream.%Save()
    Set sc = $SYSTEM.OBJ.Load(path, "ck")
    Quit sc
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

}
