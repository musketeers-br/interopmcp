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
    Quit $$$OK
}
}
