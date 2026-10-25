Class br.musketeers.InteropMCP.Demo.PayLookupBS Extends Ens.BusinessService
{

Parameter REQUESTCLASS = "br.musketeers.InteropMCP.Demo.PayLookupRequest";
Parameter AIGATEWAY = "readonly";
Parameter AIGATEWAYDESC = "Verify payment status for an order";

Method OnProcessInput(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    Do ..SendRequestSync("AuditProcess", pRequest, 15, .auditResp)
    Set pResponse = ##class(br.musketeers.InteropMCP.Demo.PayLookupResponse).%New()
    Set pResponse.Status = "Compensated"
    Set pResponse.Paid = 1
    Set pResponse.Amount = 150.75
    Quit $$$OK
}

}
