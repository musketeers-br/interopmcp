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
ClassMethod Invoke(pTool As %String, pParams As %DynamicObject, pAgent As %String, Output pInvocationId As %String, Output pResponse As %DynamicObject, pReuseInvocationId As %String = "") As %Status
{
    Set pResponse = ##class(%DynamicObject).%New()
    Set sc = ##class(br.musketeers.InteropMCP.Registry).GetToolDefinition(pTool, .def)
    If $$$ISERR(sc) Quit sc
    Set agent = ##class(br.musketeers.InteropMCP.Guardrails).ResolveAgent(pAgent)
    Set ^||InteropMCP.AgentIdentity = agent
    If $Get(^||InteropMCP.Source) = "" Set ^||InteropMCP.Source = "MCP"
    If pReuseInvocationId '= "" {
        Set pInvocationId = pReuseInvocationId
    } Else {
        Set sc = ##class(br.musketeers.InteropMCP.Invocations).CreateInvocation(pTool, agent, pParams, .pInvocationId)
        If $$$ISERR(sc) Quit sc
    }
    Set requestClass = def.requestClass
    Set request = $CLASSMETHOD(requestClass, "%New")
    Set iter = pParams.%GetIterator()
    While iter.%GetNext(.key, .value) {
        Set $PROPERTY(request, key) = value
    }
    // A business host that performs the run in the background needs to know
    // which invocation the run belongs to, so it can record the outcome
    // against the record the caller is polling. Only requests that carry the
    // property are given it.
    Try {
        Set $PROPERTY(request, "GatewayInvocationId") = pInvocationId
    } Catch ex {
        Set tIgnored = 1
    }
    Set serviceName = def.serviceName
    Set logData = ##class(%DynamicObject).%New()
    Do logData.%Set("tool", pTool)
    Do logData.%Set("service", serviceName)

    // Native trace: a direct invocation has no production message of its own,
    // so the gateway writes the request/response pair itself. A header failure
    // is logged but does not stop the tool; the invocation store remains the
    // authoritative audit record.
    Set source = $Get(^||InteropMCP.Source)
    If source = "" Set source = "MCP"
    Set sessionId = +$Get(^||InteropMCP.SessionId, 0)
    Set requestHeaderId = 0
    Set headerSc = ##class(br.musketeers.InteropMCP.HeaderAudit).CreateRequest(source, serviceName, request, .sessionId, "MCP tool: "_pTool, .requestHeaderId)
    If $$$ISERR(headerSc) {
        Do logData.%Set("headerError", $System.Status.GetErrorText(headerSc))
        Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "invoker", "Message header not created", logData)
        Set requestHeaderId = 0
    } Else {
        Set ^||InteropMCP.SessionId = sessionId
    }

    Set failureReason = ""
    Set sc = ##class(Ens.Director).CreateBusinessService(serviceName, .bs)
    If $$$ISERR(sc) {
        Do ##class(br.musketeers.InteropMCP.Log).Write("error", "invoker", "CreateBusinessService failed", logData)
        Set respDyn = ##class(%DynamicObject).%New()
        If requestHeaderId {
            Set respHeaderId = 0
            Set respSc = ##class(br.musketeers.InteropMCP.HeaderAudit).CreateResponse(requestHeaderId, "", 8, sc, .respHeaderId)
            If $$$ISERR(respSc) Do logData.%Set("responseHeaderError", $System.Status.GetErrorText(respSc))
            Do ##class(br.musketeers.InteropMCP.HeaderAudit).Complete(requestHeaderId, 8, sc)
        }
        Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "failed", respDyn, "The business service could not be created.", requestHeaderId)
    } ElseIf def.async {
        // An asynchronous entry runs in a background job, so the connection
        // that carries the call is released immediately. A run that outlasts
        // the response window of the transport would otherwise hold that
        // connection - and, with a single-connection bridge, take the whole
        // endpoint down for the duration.
        // Publish the header id before scheduling: the background job may start
        // before this method resumes.
        If requestHeaderId Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "executing", "", "", requestHeaderId)
        Set sc = ##class(Ens.BusinessService).CallProcessInputAsync(serviceName, request, .requestId)
        If $$$ISERR(sc) {
            Do ##class(br.musketeers.InteropMCP.Log).Write("error", "invoker", "ProcessInput failed", logData)
            Set respDyn = ##class(%DynamicObject).%New()
            If requestHeaderId {
                Set respHeaderId = 0
                Set respSc = ##class(br.musketeers.InteropMCP.HeaderAudit).CreateResponse(requestHeaderId, "", 8, sc, .respHeaderId)
                If $$$ISERR(respSc) Do logData.%Set("responseHeaderError", $System.Status.GetErrorText(respSc))
                Do ##class(br.musketeers.InteropMCP.HeaderAudit).Complete(requestHeaderId, 8, sc)
            }
            Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "failed", respDyn, "The business service could not be started.", requestHeaderId)
        } Else {
            Do ##class(br.musketeers.InteropMCP.Log).Write("info", "invoker", "Business service scheduled", logData)
            If requestHeaderId Do ##class(br.musketeers.InteropMCP.HeaderAudit).MarkQueued(requestHeaderId)
            Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "executing", "", "", requestHeaderId)
        }
    } Else {
        Set sc = $$$OK
        Try {
            Set bs.%SessionId = sessionId
        } Catch ex {
            Set tIgnored = 1
        }
        Try {
            Set sc = bs.ProcessInput(request, .response)
        } Catch ex {
            // A business host that throws hands back the reason; a business host
            // that returns a failing status does not. Both end as a failed
            // invocation, and the reason is what makes the failure diagnosable.
            Set sc = ex.AsStatus()
            Set failureReason = ex.DisplayString()
        }
        If $$$ISERR(sc) {
            Do ##class(br.musketeers.InteropMCP.Log).Write("error", "invoker", "ProcessInput failed", logData)
            // The response, when the business host produced one, carries the reason:
            // it is serialised into the audit record so the failure is diagnosable.
            Set respDyn = ##class(%DynamicObject).%New()
            If $IsObject(response) {
                Set respDyn = ##class(%Library.DynamicObject).%FromObject(response)
            }
            If failureReason = "" Set failureReason = "The business service did not complete."
            If requestHeaderId {
                Set respHeaderId = 0
                Set respSc = ##class(br.musketeers.InteropMCP.HeaderAudit).CreateResponse(requestHeaderId, response, 8, sc, .respHeaderId)
                If $$$ISERR(respSc) Do logData.%Set("responseHeaderError", $System.Status.GetErrorText(respSc))
                Do ##class(br.musketeers.InteropMCP.HeaderAudit).Complete(requestHeaderId, 8, sc)
            }
            Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "failed", respDyn, failureReason, requestHeaderId)
        } Else {
            Do ##class(br.musketeers.InteropMCP.Log).Write("info", "invoker", "Business service executed", logData)
            // Serialize the Ens.Response into a DynamicObject for audit storage
            If $IsObject(response) {
                Set respDyn = ##class(%Library.DynamicObject).%FromObject(response)
            } Else {
                Set respDyn = ##class(%DynamicObject).%New()
            }
            If requestHeaderId {
                Set respHeaderId = 0
                Set respSc = ##class(br.musketeers.InteropMCP.HeaderAudit).CreateResponse(requestHeaderId, response, 9, "", .respHeaderId)
                If $$$ISERR(respSc) Do logData.%Set("responseHeaderError", $System.Status.GetErrorText(respSc))
                Do ##class(br.musketeers.InteropMCP.HeaderAudit).Complete(requestHeaderId, 9)
            }
            Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "completed", respDyn, "", requestHeaderId)
        }
    }
    Quit sc
}

}
