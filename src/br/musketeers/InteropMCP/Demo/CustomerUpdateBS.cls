Class br.musketeers.InteropMCP.Demo.CustomerUpdateBS Extends Ens.BusinessService
{

Parameter REQUESTCLASS = "br.musketeers.InteropMCP.Demo.CustomerUpdateRequest";
Parameter AIGATEWAY = "write";
Parameter AIGATEWAYDESC = "Update customer delivery address";

Method OnProcessInput(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    Do ..SendRequestSync("AuditProcess", pRequest, 15, .auditResp)
    Set pResponse = ##class(br.musketeers.InteropMCP.Demo.CustomerUpdateResponse).%New()
    Set pResponse.Status = "Updated"
    Set pResponse.Updated = 1
    Quit $$$OK
}
}
