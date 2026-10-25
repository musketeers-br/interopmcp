Class br.musketeers.InteropMCP.Demo.AuditProcess Extends Ens.BusinessProcess
{

Parameter RESPONSETIMEOUTDEFAULT = 15;

Method OnRequest(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    Set tSC = ..SendRequestSync("AuditOperation", pRequest, 15, .pResponse)
    Quit tSC}
Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
