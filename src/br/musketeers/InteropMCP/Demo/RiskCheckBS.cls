Class br.musketeers.InteropMCP.Demo.RiskCheckBS Extends Ens.BusinessService
{

Parameter REQUESTCLASS = "br.musketeers.InteropMCP.Demo.RiskCheckRequest";
Parameter AIGATEWAY = "critical";
Parameter AIGATEWAYDESC = "Critical risk assessment requiring human approval";

Method OnProcessInput(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    Do ..SendRequestSync("AuditProcess", pRequest, 15, .auditResp)
    Set pResponse = ##class(br.musketeers.InteropMCP.Demo.RiskCheckResponse).%New()
    Set pResponse.Status = "Approved"
    Set pResponse.Result = "Clear"
    Quit $$$OK
}
}
