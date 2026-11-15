/// IRIS MCP Gateway - the demonstration's REST entry point for the agent.
/// A web application of Type 2 (REST) at path /api/agent dispatches
/// POST /api/agent/assess into this class, which hands the caller's goal to
/// the agent's business host and returns the agent's answer.
/// The endpoint is synchronous: the caller's request waits for the run.
/// Responsibilities:
/// - Read and validate the request. The goal is required and is never chosen
///   by the endpoint - an empty goal is answered with an error, never with a
///   goal the endpoint invented.
/// - Extract the text of an attached PDF, when one is attached, with the
///   platform's embedded Python: the agent reads text, not binary.
/// - Run the agent through its own business host, so that the run is recorded
///   in the gateway's invocation store like every other invocation.
/// - Answer with JSON, or with a diagnosable error.
/// The endpoint reaches the agent the same way the gateway does - through the
/// production's configuration item - so the run is guarded, audited and
/// recorded exactly as a call through the MCP endpoint would be.
Class br.musketeers.InteropMCP.Demo.AgentRESTService Extends %CSP.REST
{

/// The configuration item of the demonstration's production that runs the
/// agent.
Parameter AgentHostItem = "AgentHost";

/// The Python module that extracts the text of an attached PDF. It lives in
/// the instance's Python path.
Parameter PdfModule = "interopmcp_pdf";

/// The largest request body the endpoint reads, in characters. This is the
/// platform's maximum string length: a longer body cannot be read into a
/// string, so the endpoint's limit and the platform's limit are one and the
/// same.
Parameter MaxBodySize = 3600000;

/// The largest amount of a document's text handed to the agent, in
/// characters. The agent's goal is bounded (see Agent.Request.Goal), so a
/// document whose text is longer is truncated - and the truncation is stated
/// in the goal the agent receives, so the agent knows it is not seeing the
/// whole document.
Parameter MaxDocumentText = 50000;

/// <class>Ens.DataType.MessageStatus</class> values used for the message
/// header this endpoint writes, so the run is visible in the Message Viewer
/// with the outcome it actually reached. The header is created before the run
/// and updated afterwards; the value must be the datatype's numeric code, not
/// a display name, or the save fails validation.
Parameter MsgStatusCreated = 1;

Parameter MsgStatusCompleted = 9;

Parameter MsgStatusError = 8;

Parameter APPLICATION = "br.musketeers.InteropMCP.Demo.AgentRESTService";

Parameter CHARSET = "utf-8";

Parameter CONTENTTYPE = "application/json";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
    <Routes>
    <Route Url="/assess" Method="POST" Call="AssessSupplier"/>
    </Routes>
}

/// Runs the agent against the caller's goal and answers with its result.
ClassMethod AssessSupplier() As %Status
{
    Set tText = ..ReadBody()
    Set tRequest = ""
    If tText '= "" {
        Try {
            Set tDyn = ##class(%DynamicObject).%FromJSON(tText)
            Set tRequest = ##class(br.musketeers.InteropMCP.Demo.AgentAssessRequest).%New()
            Set tRequest.Goal = tDyn.%Get("Goal", "")
            Set tRequest.CNPJ = tDyn.%Get("CNPJ", "")
            Set tRequest.DocumentBase64 = tDyn.%Get("DocumentBase64", "")
        } Catch ex {
            Set tRequest = ""
        }
    }
    If '$IsObject(tRequest) {
        Do ..WriteError(400, "The request body is not a JSON object.")
        Return $$$OK
    }

    // The goal is the caller's, never the endpoint's. An empty goal is a
    // malformed request, not an invitation to guess what the caller wanted.
    Set tGoal = tRequest.Goal
    If tGoal = "" {
        Do ..WriteError(400, "Goal is required: the endpoint does not choose one for the caller.")
        Return $$$OK
    }

    Set tCnpj = tRequest.CNPJ
    If tCnpj '= "" {
        Set tGoal = tGoal _ $C(10, 10) _ "CNPJ do fornecedor: "_tCnpj
    }

    // An attached document is delivered to the agent as text.
    Set tDocument = tRequest.DocumentBase64
    If tDocument '= "" {
        Set tDocumentText = ""
        Try {
            Set tDocumentText = ..ExtractPDFText(tDocument)
        } Catch ex {
            Do ..WriteError(400, "The attached document could not be read as a PDF: "_ex.DisplayString())
            Return $$$OK
        }
        // Empty string means valid PDF with no extractable text - that's OK.
        If $Length(tDocumentText) > ..#MaxDocumentText {
            Set tDocumentText = $Extract(tDocumentText, 1, ..#MaxDocumentText) _
                $C(10) _ "[texto do documento truncado em "_..#MaxDocumentText_" caracteres]"
        }
        Set tGoal = tGoal _ $C(10, 10) _ "--- TEXTO DO DOCUMENTO ANEXO ---" _ $C(10) _ tDocumentText
    }

    // The run is recorded in the gateway's invocation store, like every other
    // invocation, so that it can be audited and correlated with the agent's
    // own record of what it did.
    Set tParams = ##class(%DynamicObject).%New()
    Do tParams.%Set("Goal", tGoal)
    Do tParams.%Set("CNPJ", tCnpj)
    Set tInvocationId = ""
    Set tSC = ##class(br.musketeers.InteropMCP.Invocations).CreateInvocation(..#AgentHostItem, $USERNAME, tParams, .tInvocationId)
    If $$$ISERR(tSC) {
        Do ..WriteError(500, "The invocation could not be recorded: "_$SYSTEM.Status.GetErrorText(tSC))
        Return $$$OK
    }

    Set tResponse = ..RunAgent(tGoal, tInvocationId, .tSC)
    If $$$ISERR(tSC) {
        Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(tInvocationId, "failed", "", $SYSTEM.Status.GetErrorText(tSC), 0)
        Do ..WriteError(500, "The agent's run failed: "_$SYSTEM.Status.GetErrorText(tSC))
        Return $$$OK
    }

    Set tOut = ##class(br.musketeers.InteropMCP.Demo.AgentAssessResponse).%New()
    Set tOut.Status = tResponse.Status
    Set tOut.InvocationId = tInvocationId
    Set tOut.Answer = tResponse.Answer
    Set tOut.CapabilitiesUsed = tResponse.CapabilitiesUsed
    Set tOut.Retrievals = tResponse.Retrievals
    Do ..WriteJSON(tOut)
    Return $$$OK
}

/// Runs the agent through its own business host and returns its response.
/// The host is the production's configuration item, reached the same way the
/// gateway reaches it. A run that fails is reported through the status, not
/// thrown: the endpoint answers with the reason.
ClassMethod RunAgent(pGoal As %String, pInvocationId As %String, Output pSC As %Status) As br.musketeers.InteropMCP.Agent.Response
{
    Set pSC = $$$OK
    Set ^||InteropMCP.AgentIdentity = $USERNAME
    Set ^||InteropMCP.Source = "REST"
    Set tRequest = ##class(br.musketeers.InteropMCP.Agent.Request).%New()
    Set tRequest.Goal = pGoal
    Set tRequest.GatewayInvocationId = pInvocationId

    // Save the request so it gets an ID for the message header.
    Set tSC = tRequest.%Save()
    If $$$ISERR(tSC) {
        Set pSC = tSC
        Quit ""
    }

    // The REST entry point is a gateway hop, not a production item. Its
    // request/response pair is written explicitly so the run appears in the
    // Message Viewer with the same session as the agent's tool calls.
    Set tSessionId = +$Get(^||InteropMCP.SessionId, 0)
    Set tMsgHeaderId = 0
    Set tHeaderSC = ##class(br.musketeers.InteropMCP.HeaderAudit).CreateRequest("REST", ..#AgentHostItem, tRequest, .tSessionId, "REST agent run", .tMsgHeaderId)
    If $$$ISERR(tHeaderSC) {
        Set tHeaderData = ##class(%DynamicObject).%New()
        Do tHeaderData.%Set("error", $System.Status.GetErrorText(tHeaderSC))
        Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "agent", "REST message header not created", tHeaderData)
        Set tMsgHeaderId = 0
    } Else {
        Set ^||InteropMCP.SessionId = tSessionId
    }

    // Get the production business service instance and deliver through it.
    Set tService = ""
    Set pSC = ##class(Ens.Director).CreateBusinessService(..#AgentHostItem, .tService)
    If $$$ISERR(pSC) {
        Do ..FinishFailure(tMsgHeaderId, pSC, pInvocationId)
        Quit ""
    }
    If '$IsObject(tService) {
        Set pSC = $$$ERROR($$$GeneralError, "AgentHost service instance is null")
        Do ..FinishFailure(tMsgHeaderId, pSC, pInvocationId)
        Quit ""
    }

    Try {
        Set tService.%SessionId = tSessionId
    } Catch ex {
        Set tIgnored = 1
    }

    Set tResponse = ""
    Try {
        Set pSC = tService.ProcessInput(tRequest, .tResponse)
    } Catch ex {
        Set pSC = $$$ERROR($$$GeneralError, ex.DisplayString())
    }
    If $$$ISERR(pSC) {
        Set tResponse = ""
        Do ..FinishFailure(tMsgHeaderId, pSC, pInvocationId)
        Quit ""
    }

    If tMsgHeaderId {
        Set tRespHeaderId = 0
        Set tRespSC = ##class(br.musketeers.InteropMCP.HeaderAudit).CreateResponse(tMsgHeaderId, tResponse, 9, "", .tRespHeaderId)
        If $$$ISERR(tRespSC) {
            Set tHeaderData = ##class(%DynamicObject).%New()
            Do tHeaderData.%Set("error", $System.Status.GetErrorText(tRespSC))
            Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "agent", "REST response header not created", tHeaderData)
        }
        Do ##class(br.musketeers.InteropMCP.HeaderAudit).Complete(tMsgHeaderId, 9)
    }
    Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "completed", "", "", tMsgHeaderId)
    Return tResponse
}

/// Records a failed REST run against the request header and the invocation.
ClassMethod FinishFailure(pHeaderId As %Integer, pSC As %Status, pInvocationId As %String) As %Status
{
    If pHeaderId {
        Set respHeaderId = 0
        Set respSC = ##class(br.musketeers.InteropMCP.HeaderAudit).CreateResponse(pHeaderId, "", 8, pSC, .respHeaderId)
        If $$$ISERR(respSC) {
            Set headerData = ##class(%DynamicObject).%New()
            Do headerData.%Set("error", $System.Status.GetErrorText(respSC))
            Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "agent", "REST error response header not created", headerData)
        }
        Do ##class(br.musketeers.InteropMCP.HeaderAudit).Complete(pHeaderId, 8, pSC)
    }
    If pInvocationId '= "" {
        Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(pInvocationId, "failed", "", $System.Status.GetErrorText(pSC), pHeaderId)
    }
    Quit $$$OK
}

/// Extracts the text of an attached PDF with the platform's embedded Python.
/// Returns the text (empty string if the PDF is valid but has no extractable text).
/// Throws an exception if the document is not a valid PDF or cannot be decoded.
ClassMethod ExtractPDFText(pBase64 As %String) As %String
{
    Set tText = ""
    Set tModule = ##class(%SYSTEM.Python).Import(..#PdfModule)
    If $IsObject(tModule) {
        Set tText = tModule.extractText(pBase64)
    }
    Quit tText
}

/// Reads the request body. An unreadable body is the empty string, which the
/// caller reports as a malformed request.
ClassMethod ReadBody() As %String
{
    Set tText = ""
    Try {
        // %request.Content is a %CSP.BinaryStream at runtime; the JSON body is
        // text, so reading it as a string is safe.
        Set tStream = %request.Content
        If $IsObject(tStream) {
            Do tStream.Rewind()
            Set tText = tStream.Read(..#MaxBodySize)
        }
    } Catch ex {
        Set tText = ""
    }
    Quit tText
}

/// Writes the answer as JSON.
ClassMethod WriteJSON(pObject As %RegisteredObject) As %Status
{
    Set %response.ContentType = "application/json; charset=utf-8"
    Set tJson = {}
    Set tJson.Status = pObject.Status
    Set tJson.InvocationId = pObject.InvocationId
    Set tJson.Answer = pObject.Answer
    Set tJson.CapabilitiesUsed = ##class(%DynamicArray).%FromJSON(pObject.CapabilitiesUsed)
    Set tJson.Retrievals = ##class(%DynamicArray).%FromJSON(pObject.Retrievals)
    Write tJson.%ToJSON()
    Quit $$$OK
}

/// Writes an error as JSON, with the status the caller sees.
ClassMethod WriteError(pStatus As %Integer, pMessage As %String) As %Status
{
    Set %response.Status = pStatus
    Set %response.ContentType = "application/json; charset=utf-8"
    Set tJson = {}
    Set tJson.status = "failed"
    Set tJson.error = pMessage
    Write tJson.%ToJSON()
    Quit $$$OK
}

}
