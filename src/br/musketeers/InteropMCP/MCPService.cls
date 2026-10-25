/// IRIS MCP Gateway - MCP protocol dispatcher.
/// AI HUB MCP service bound to the gateway toolset. A web application of
/// Type 18 (MCP service) at path /mcp/interopmcp dispatches incoming MCP
/// JSON-RPC traffic into this class, which resolves the toolset declared in
/// the SPECIFICATION parameter (br.musketeers.InteropMCP.ToolSet) and exposes its included
/// tools to connected agents.
/// Provisioned by br.musketeers.InteropMCP.Setup (dev or prod authentication posture);
/// this class holds no business logic of its own.
Class br.musketeers.InteropMCP.MCPService Extends %AI.MCP.Service
{

/// Toolset specification consumed by the AI HUB MCP layer: every tool
/// included in br.musketeers.InteropMCP.ToolSet becomes callable through this service.
Parameter SPECIFICATION = "br.musketeers.InteropMCP.ToolSet";

}
