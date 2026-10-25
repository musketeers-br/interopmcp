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

}
