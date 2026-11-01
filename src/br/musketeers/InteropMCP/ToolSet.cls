/// IRIS MCP Gateway - AI HUB toolset binding.
/// Declares which classes contribute agent-facing tools to the gateway MCP
/// endpoint. The XData Definition includes:
/// - br.musketeers.InteropMCP.GeneratedTools: code-generated wrapper methods, one per
///   Business Service published by br.musketeers.InteropMCP.Registry.BuildCatalog
/// - br.musketeers.InteropMCP.InvocationStatusTools: the fixed status polling tool
/// The toolset is bound to the endpoint through br.musketeers.InteropMCP.MCPService
/// (SPECIFICATION parameter) and is the only surface agents discover via
/// tools/list. Editing this XData changes what agents can see; the generated
/// tools class itself must not be edited (it is regenerated on catalog
/// builds).
Class br.musketeers.InteropMCP.ToolSet Extends %AI.ToolSet [ DependsOn = br.musketeers.InteropMCP.GeneratedTools ]
{

/// Toolset manifest consumed by the AI HUB MCP layer: description shown to
/// agents plus the included tool contributor classes.
XData Definition [ MimeType = text/xml ]
{
<ToolSet>
  <Description>IRIS MCP Gateway tool catalog</Description>
  <Include Class="br.musketeers.InteropMCP.GeneratedTools"></Include>
  <Include Class="br.musketeers.InteropMCP.InvocationStatusTools"></Include>
</ToolSet>
}

/// Dispatches a tool call to the class that owns the tool. A fresh instance
/// of the owning class is created for every call: the AI HUB caches the
/// toolset instance - and the tool instances it creates - for the lifetime
/// of the serving process, and a cached instance keeps the class definition
/// it was created with. Creating the instance per call makes a recompiled
/// generated-tools class effective without restarting the process, which is
/// what a catalog rebuild produces.
Method %Invoke(toolname As %String, args As %DynamicObject) As %Any
{
    Set tool = $ZCONVERT(toolname, "U")
    If tool = "GETINVOCATIONSTATUS" {
        Set instance = ##class(br.musketeers.InteropMCP.InvocationStatusTools).%New()
        Quit instance.%Invoke(toolname, args)
    }
    Set instance = ##class(br.musketeers.InteropMCP.GeneratedTools).%New()
    Quit instance.%Invoke(toolname, args)
}

}
