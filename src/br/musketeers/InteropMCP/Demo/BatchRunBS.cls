Class br.musketeers.InteropMCP.Demo.BatchRunBS Extends Ens.BusinessService
{

Parameter REQUESTCLASS = "br.musketeers.InteropMCP.Demo.BatchRunRequest";
Parameter AIGATEWAY = "readonly";
Parameter AIGATEWAYASYNC = "1";
Parameter AIGATEWAYDESC = "Long-running batch report generation";

Method OnProcessInput(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    Do ..SendRequestSync("AuditProcess", pRequest, 15, .auditResp)
    Set pResponse = ##class(br.musketeers.InteropMCP.Demo.BatchRunResponse).%New()
    Set pResponse.Status = "Done"
    Set pResponse.JobId = $SYSTEM.Util.CreateGUID()
    // The run is dispatched asynchronously, so the answer reaches the caller
    // through the invocation it polls. The gateway hands the invocation's id
    // with the request, and the business host records the outcome against it.
    Set invocationId = ""
    Try {
        Set invocationId = pRequest.GatewayInvocationId
    } Catch ex {
        Set invocationId = ""
    }
    Set requestHeaderId = 0
    If invocationId '= "" {
        Set rid = ##class(br.musketeers.InteropMCP.Invocations).GetRowId(invocationId)
        If rid '= "" {
            Set inv = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(rid)
            If $IsObject(inv) {
                Set requestHeaderId = +inv.MessageHeaderId
                If requestHeaderId {
                    Set header = ##class(Ens.MessageHeader).%OpenId(requestHeaderId)
                    If $IsObject(header) {
                        Try {
                            Set ..%SessionId = header.SessionId
                        } Catch ex {
                            Set tIgnored = 1
                        }
                    }
                }
            }
        }
    }
    If invocationId '= "" {
        Set respDyn = ##class(%Library.DynamicObject).%FromObject(pResponse)
        If requestHeaderId {
            Set respHeaderId = 0
            Set respSC = ##class(br.musketeers.InteropMCP.HeaderAudit).CreateResponse(requestHeaderId, pResponse, 9, "", .respHeaderId)
            If $$$ISERR(respSC) {
                Set headerData = ##class(%DynamicObject).%New()
                Do headerData.%Set("error", $System.Status.GetErrorText(respSC))
                Do ##class(br.musketeers.InteropMCP.Log).Write("warn", "invoker", "Batch response header not created", headerData)
            }
            Do ##class(br.musketeers.InteropMCP.HeaderAudit).Complete(requestHeaderId, 9)
        }
        Do ##class(br.musketeers.InteropMCP.Invocations).UpdateStatus(invocationId, "completed", respDyn, "", requestHeaderId)
    }
    Quit $$$OK
}
}
