/// IRIS MCP Gateway - Business Service invoker.
/// This class embodies the gateway's ONLY interaction with an
/// Interoperability production: it fires the mapped Business Service through
/// the documented direct-invocation pattern
/// (Ens.Director.CreateBusinessService + ProcessInput) and never writes into
/// production structures. Native traceability is produced by the production
/// components themselves (the service forwards messages downstream).
/// Responsibilities:
/// - Record the invocation in the audit store before touching the production
/// - Instantiate the typed request class resolved from the tool definition
/// - Fill request properties dynamically from the validated call arguments
/// - Map failures (service not registered, disabled or stopped) to clear
///   agent-readable errors and persist the lifecycle transition
Class br.musketeers.InteropMCP.Invoker Extends %RegisteredObject
{

/// Executes pTool with pParams on behalf of pAgent.
/// - Resolves the tool definition from the published catalog
/// - Records the invocation (status received)
/// - Instantiates the request class (def.requestClass) and fills each
///   property from the call arguments via $PROPERTY
/// - Fires the Business Service (def.serviceName) synchronously and returns
///   its %Status; on success the invocation is marked completed
/// Outputs: pInvocationId (processing reference for the audit store) and
/// pResponse (envelope with the service name and response class).
ClassMethod Invoke(pTool As %String, pParams As %DynamicObject, pAgent As %String, Output pInvocationId As %String, Output pResponse As %DynamicObject) As %Status
{
    Set pResponse = ##class(%DynamicObject).%New()
    Set pInvocationId = ""
    Set sc = ##class(br.musketeers.InteropMCP.Registry).GetToolDefinition(pTool, .def)
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(br.musketeers.InteropMCP.Invocations).CreateInvocation(pTool, pAgent, pParams, .pInvocationId)
    If $$$ISERR(sc) Quit sc
    Set requestClass = def.requestClass
    Set request = $CLASSMETHOD(requestClass, "%New")
    Set iter = pParams.%GetIterator()
    While iter.%GetNext(.key, .value) {
        Set $PROPERTY(request, key) = value
    }
    Set serviceName = def.serviceName
    Set logData = ##class(%DynamicObject).%New()
    Do logData.%Set("tool", pTool)
    Do logData.%Set("service", serviceName)
    Set sc = ##class(Ens.Director).CreateBusinessService(serviceName, .bs)
    If $$$ISERR(sc) {
        Do ##class(br.musketeers.InteropMCP.Log).Write("error", "invoker", "CreateBusinessService failed", logData)
    } Else {
        Set sc = bs.ProcessInput(request, .response)
        If $$$ISERR(sc) {
            Do ##class(br.musketeers.InteropMCP.Log).Write("error", "invoker", "ProcessInput failed", logData)
        } Else {
            Do ##class(br.musketeers.InteropMCP.Log).Write("info", "invoker", "Business service executed", logData)
            Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "completed", pResponse, "", 0)
        }
    }
    Quit sc
}

}
