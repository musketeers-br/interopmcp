/// IRIS MCP Gateway - native message-header linkage for the audit trail.
/// The gateway invokes Business Services directly, so the hop from the gateway
/// (or from the agent) to the service does not exist as a production message.
/// This class creates the synthetic request/response pair that makes the hop
/// visible in the Message Viewer. It is deliberately a thin helper: the
/// invocation store remains the authoritative record, and a header failure is
/// reported to the caller so the invoker can decide whether it is fatal.
Class br.musketeers.InteropMCP.HeaderAudit Extends %RegisteredObject
{

/// Creates the request side of a tool call. When pSessionId is zero a native
/// session is allocated; when it is already set (an agent run) the header
/// joins that session so the whole trace stays together.
ClassMethod CreateRequest(pSource As %String, pTarget As %String, pBody As %Persistent, ByRef pSessionId As %Integer, pDescription As %String, Output pHeaderId As %Integer) As %Status
{
    Set pHeaderId = 0
    Set sc = $$$OK
    If $IsObject(pBody) && (pBody.%Id() = "") {
        Set sc = pBody.%Save()
        If $$$ISERR(sc) Quit sc
    }

    Set header = ""
    If +pSessionId = 0 {
        Set newSession = ""
        Set superSession = ""
        Set sc = ##class(Ens.MessageHeader).NewRequestMessage(.header, pBody, .newSession, .superSession)
        If $$$ISOK(sc) && $IsObject(header) {
            Set pSessionId = +newSession
        } Else {
            Set header = ""
            Set sc = $$$OK
        }
    }
    If '$IsObject(header) {
        If +pSessionId = 0 Set pSessionId = ..NextSession()
        Set header = ##class(Ens.MessageHeader).%New()
        Set header.SessionId = pSessionId
    }

    Set header.SourceConfigName = pSource
    Set header.TargetConfigName = pTarget
    Set header.Type = 1
    Set header.Invocation = 2
    Set header.SourceBusinessType = 1
    Set header.TargetBusinessType = 1
    Set header.SessionId = pSessionId
    Set header.Status = 1
    Set header.TimeCreated = ##class(Ens.DataType.UTC).timeUTC()
    Set header.TimeProcessed = ""
    Set header.Description = $Extract(pDescription, 1, 200)
    If $IsObject(pBody) {
        Set header.MessageBodyClassName = pBody.%ClassName(1)
        Set header.MessageBodyId = pBody.%Id()
    }
    Set sc = header.%Save()
    If $$$ISERR(sc) Quit sc
    Set pHeaderId = header.%Id()
    Quit $$$OK
}

/// Creates the response side linked to pRequestHeaderId. The body may be empty
/// when the call failed before the service produced a response.
ClassMethod CreateResponse(pRequestHeaderId As %Integer, pBody, pStatus As %Integer, pErrorStatus As %Status, Output pResponseHeaderId As %Integer) As %Status
{
    Set pResponseHeaderId = 0
    Set request = ##class(Ens.MessageHeader).%OpenId(pRequestHeaderId)
    If '$IsObject(request) Quit $$$ERROR($$$GeneralError, "Request header not found: "_pRequestHeaderId)

    If $IsObject(pBody) && (pBody.%Id() = "") {
        Set sc = pBody.%Save()
        If $$$ISERR(sc) Quit sc
    }

    Set response = ##class(Ens.MessageHeader).%New()
    Set response.SourceConfigName = request.TargetConfigName
    Set response.TargetConfigName = request.SourceConfigName
    Set response.Type = 2
    Set response.Invocation = 2
    Set response.SourceBusinessType = request.TargetBusinessType
    Set response.TargetBusinessType = request.SourceBusinessType
    Set response.SessionId = request.SessionId
    Set response.CorrespondingMessageId = pRequestHeaderId
    Set response.Status = pStatus
    Set response.TimeCreated = ##class(Ens.DataType.UTC).timeUTC()
    Set response.TimeProcessed = response.TimeCreated
    Set response.Description = $Extract(request.Description, 1, 200)
    If $IsObject(pBody) {
        Set response.MessageBodyClassName = pBody.%ClassName(1)
        Set response.MessageBodyId = pBody.%Id()
    }
    If pErrorStatus '= "" {
        If $$$ISERR(pErrorStatus) {
            Set response.ErrorStatus = pErrorStatus
            Set response.IsError = 1
        }
    }
    Set sc = response.%Save()
    If $$$ISERR(sc) Quit sc
    Set pResponseHeaderId = response.%Id()
    Quit $$$OK
}

/// Marks an asynchronous request as queued without pretending it has finished.
ClassMethod MarkQueued(pHeaderId As %Integer) As %Status
{
    If +pHeaderId = 0 Quit $$$OK
    Set header = ##class(Ens.MessageHeader).%OpenId(pHeaderId)
    If '$IsObject(header) Quit $$$ERROR($$$GeneralError, "Message header not found: "_pHeaderId)
    Set header.Status = 2
    Set header.TimeProcessed = ""
    Quit header.%Save()
}

/// Moves the request header to its terminal state.
ClassMethod Complete(pHeaderId As %Integer, pStatus As %Integer, pErrorStatus As %Status = "") As %Status
{
    If +pHeaderId = 0 Quit $$$OK
    Set header = ##class(Ens.MessageHeader).%OpenId(pHeaderId)
    If '$IsObject(header) Quit $$$ERROR($$$GeneralError, "Message header not found: "_pHeaderId)
    Set header.Status = pStatus
    Set header.TimeProcessed = ##class(Ens.DataType.UTC).timeUTC()
    If pErrorStatus '= "" {
        If $$$ISERR(pErrorStatus) {
            Set header.ErrorStatus = pErrorStatus
            Set header.IsError = 1
        }
    }
    Quit header.%Save()
}

/// Gateway-owned session sequence. Native sessions are small numbers; starting
/// well above them keeps synthetic traces from colliding with production ones.
ClassMethod NextSession() As %Integer
{
    If '$Data(^InteropMCP.SessionId) Set ^InteropMCP.SessionId = 100000000
    Quit $Increment(^InteropMCP.SessionId)
}

}
