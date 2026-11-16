/// IRIS MCP Gateway - the business host that runs the agent.
/// This is the entry point the gateway calls, by production config item name,
/// exactly as it reaches every other business service. That is deliberate: the
/// existing invoker, guardrail, approval, and invocation path then apply to a
/// call that reaches the agent with no change at all, and the agent's own
/// actions - the capabilities it invokes - go through the same path, so the
/// classification and the human approval gate are applied to them as they are
/// to a direct caller's.
/// The host owns no processing of its own. The adapter is the component that
/// runs the agent, and the host carries the goal to it and hands the answer
/// back. One implementation, two doors - the adapter's polling and the
/// gateway's direct call - so the two cannot drift apart.
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
/// The run belongs to the adapter: the host forwards the goal and hands back
/// what the adapter produced.
Method OnProcessInput(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
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

	// The agent runs in the adapter, with the configuration of the item this
	// host runs as. This host is the origin of the run, so it names itself as
	// the source of the calls the agent makes on its own. Delegates through
	// ..Adapter, the instance the framework created for this production item,
	// so the ADAPTER parameter of the item (and of any subclass) is honored.
	Set response = ""
	Set sc = ..Adapter.ExecuteAgent(..%ConfigName, goal, invocationId, "AgentHost", .response)
	Set pResponse = response

	If $$$ISERR(sc) {
		// The reason travels in the response the adapter produced: a business
		// host that fails does not hand its response back, so the reason is
		// read from the response rather than from the status.
		Set reason = ""
		If $IsObject(response) {
			Try {
				Set reason = response.Answer
			} Catch ex {
				Set reason = ""
			}
		}
		If reason = "" Set reason = "The agent run did not complete."
		Throw ##class(%Exception.General).%New(reason)
	}
	Quit sc
}

}
