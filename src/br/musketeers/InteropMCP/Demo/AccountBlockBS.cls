Class br.musketeers.InteropMCP.Demo.AccountBlockBS Extends Ens.BusinessService
{

Parameter REQUESTCLASS = "br.musketeers.InteropMCP.Demo.AccountBlockRequest";
Parameter AIGATEWAY = "critical";
Parameter AIGATEWAYDESC = "Critical account blocking requiring human approval";

Method OnProcessInput(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    Do ..SendRequestSync("AuditProcess", pRequest, 15, .auditResp)
    Set pResponse = ##class(br.musketeers.InteropMCP.Demo.AccountBlockResponse).%New()
    Set pResponse.Status = "Blocked"
    Set pResponse.BlockedAt = $ZDateTime($Horolog, 3)
    Quit $$$OK
}
}