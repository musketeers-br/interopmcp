/// IRIS MCP Gateway - the demonstration's REST entry point for the agent.
/// A web application of Type 2 (REST) at path /api/agent dispatches
/// POST /api/agent/assess into this class, which hands the caller's goal to
/// the production, and GET /api/agent/status back to the caller that waits
/// for the outcome.
/// The endpoint is asynchronous: it queues the caller's goal and answers as
/// soon as the work is accepted, and the caller collects the outcome by
/// polling. The production's inbound adapter is what picks the work up and
/// runs it, so the endpoint never holds an HTTP connection for the length of
/// an agent run.
/// Responsibilities:
/// - Read and validate the request. The goal is required and is never chosen
///   by the endpoint - an empty goal is answered with an error, never with a
///   goal the endpoint invented.
/// - Extract the text of an attached PDF, when one is attached, with the
///   platform's embedded Python: the agent reads text, not binary.
/// - Record the run in the gateway's invocation store, like every other
///   invocation, so that it can be audited and correlated with the agent's
///   own record of what it did.
/// - Queue the run and answer with the reference the caller polls.
/// - Answer a polling call with the state of the run and its outcome.
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

Parameter APPLICATION = "br.musketeers.InteropMCP.Demo.AgentRESTService";

Parameter CHARSET = "utf-8";

Parameter CONTENTTYPE = "application/json";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
    <Route Url="/assess" Method="POST" Call="AssessSupplier"/>
    <Route Url="/status" Method="GET" Call="RunStatus"/>
    </Routes>
}

/// Queues the caller's goal for the agent and answers with the reference the
/// caller polls. The work is not run here: the production's inbound adapter
/// picks it up and hands it to the agent, and the caller collects the
/// outcome from the invocation this call records.
/// The answer is "202 Accepted": the work was accepted, not carried out.
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

    // The work is queued for the production's adapter, together with the
    // context that produced it: the caller's identity and the source it came
    // from travel with the work, because they do not survive the boundary
    // between this job and the one that runs it.
    Set tQueueId = ""
    Set tSC = ##class(br.musketeers.InteropMCP.Agent.Queue).Enqueue(tGoal, tInvocationId, $USERNAME, "REST", "", .tQueueId)
    If $$$ISERR(tSC) {
        Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(tInvocationId, "failed", "", $SYSTEM.Status.GetErrorText(tSC), 0)
        Do ..WriteError(500, "The work could not be queued: "_$SYSTEM.Status.GetErrorText(tSC))
        Return $$$OK
    }

    Set tOut = ##class(%DynamicObject).%New()
    Do tOut.%Set("status", "PENDING")
    Do tOut.%Set("invocationId", tInvocationId)
    Do tOut.%Set("queueId", tQueueId)
    Do tOut.%Set("message", "The run was queued. Poll GET /api/agent/status?invocationId="_tInvocationId_" for the outcome.")
    Do ..WriteDynamic(tOut, 202)
    Return $$$OK
}

/// Answers a caller that waits for a run: the state of the run and, when it
/// finished, its outcome. The state is one word - pending, running,
/// completed or failed - so that a caller can poll it without having to know
/// the two vocabularies the gateway keeps underneath: the queue's and the
/// invocation's.
ClassMethod RunStatus() As %Status
{
    Set tInvocationId = %request.Get("invocationId")
    If tInvocationId = "" {
        Do ..WriteError(400, "invocationId is required.")
        Return $$$OK
    }

    Set tRowId = ##class(br.musketeers.InteropMCP.Invocations).GetRowId(tInvocationId)
    If tRowId = "" {
        Do ..WriteError(404, "No invocation carries that id.")
        Return $$$OK
    }
    Set tInv = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(tRowId)

    // The queue says what the work item is doing; the invocation says what
    // the run did. A work item that was abandoned never reaches a terminal
    // invocation state, so the queue is what tells the caller that.
    Set tQueueId = ""
    Set tQueueStatus = ""
    Set tQueueError = ""
    Set tQueueSc = ##class(br.musketeers.InteropMCP.Agent.Queue).ByInvocation(tInvocationId, .tQueueId, .tQueueStatus, .tQueueError)

    Set tOut = ##class(br.musketeers.InteropMCP.Demo.AgentAssessResponse).%New()
    Set tOut.InvocationId = tInvocationId
    Set tOut.Answer = ""
    Set tOut.CapabilitiesUsed = "[]"
    Set tOut.Retrievals = "[]"

    Set tStatus = ..RunState(tInv.Status, tQueueStatus)
    Set tAnswer = ""
    If tInv.Result '= "" {
        Try {
            Set tResult = ##class(%DynamicObject).%FromJSON(tInv.Result)
            Set tAnswer = tResult.%Get("Answer")
            Set tCaps = tResult.%Get("CapabilitiesUsed")
            If tCaps '= "" Set tOut.CapabilitiesUsed = tCaps
            Set tRetr = tResult.%Get("Retrievals")
            If tRetr '= "" Set tOut.Retrievals = tRetr
        } Catch ex {
            Set tIgnored = 1
        }
    }
    If tInv.ErrorMessage '= "" {
        Set tStatus = "failed"
        If tAnswer = "" Set tAnswer = tInv.ErrorMessage
    }
    // The work item's own state has the last word on a run that never
    // reached the agent: an abandoned item is a failure the invocation
    // cannot know about.
    If tQueueStatus = "ERROR" {
        Set tStatus = "failed"
        If tAnswer = "" Set tAnswer = tQueueError
    }
    Set tOut.Status = tStatus
    Set tOut.Answer = tAnswer
    Do ..WriteJSON(tOut)
    Return $$$OK
}

/// Says where the run is, in one word. The work item's state is the
/// authority while the work is in flight, because it is what says that the
/// work was accepted and not yet picked up; the invocation's state is the
/// authority once the run has answered.
ClassMethod RunState(pInvocationStatus As %String, pQueueStatus As %String) As %String
{
    If pQueueStatus = "PENDING" Quit "pending"
    If pQueueStatus = "PROCESSING" Quit "running"
    If pQueueStatus = "COMPLETED" Quit "completed"
    If pQueueStatus = "ERROR" Quit "failed"
    If pInvocationStatus = "executing" Quit "running"
    If pInvocationStatus = "completed" Quit "completed"
    If pInvocationStatus = "failed" Quit "failed"
    Quit "pending"
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

/// Writes an answer whose shape is described by the caller itself.
ClassMethod WriteDynamic(pObject As %DynamicObject, pStatus As %Integer = 200) As %Status
{
    Set %response.Status = pStatus
    Set %response.ContentType = "application/json; charset=utf-8"
    Write pObject.%ToJSON()
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
