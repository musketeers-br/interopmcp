Class br.musketeers.InteropMCP.Demo.AuditOperation Extends Ens.BusinessOperation
{

Method OnMessage(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    Set tSC = $$$OK
    Set tDump = ##class(%DynamicObject).%New()
    Set tCd = ##class(%Dictionary.ClassDefinition).%OpenId($ClassName(pRequest))
    If $IsObject(tCd) {
        For i = 1:1:tCd.Properties.Count() {
            Set tPd = tCd.Properties.GetAt(i)
            Try {
                Do tDump.%Set(tPd.Name, $PROPERTY(pRequest, tPd.Name))
            } Catch ex {
                Set tIgnored = 1
            }
        }
    }
    Set tId = $Increment(^InteropMCP.Demo.AuditD)
    Set ^InteropMCP.Demo.AuditD(tId) = $ClassName(pRequest) _ "|" _ $ZDateTime($Horolog, 3) _ "|" _ tDump.%ToJSON()
    Set pResponse = ##class(Ens.Response).%New()
    Quit tSC
}

}
