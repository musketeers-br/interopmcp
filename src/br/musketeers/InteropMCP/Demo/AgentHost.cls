/// The demonstration production's agent host.
/// Carries the demonstration's own identity for the agent: the prompt the
/// operator wrote, the model it uses, and the capabilities it may reach. The
/// mechanics - resolving the configuration, building the agent, running it -
/// are the gateway's, so that the demonstration and any other production
/// behave the same way.
Class br.musketeers.InteropMCP.Demo.AgentHost Extends br.musketeers.InteropMCP.Agent.Host
{
}
