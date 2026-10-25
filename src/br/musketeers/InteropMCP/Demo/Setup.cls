Class br.musketeers.InteropMCP.Demo.Setup Extends %RegisteredObject
{

ClassMethod Run() As %Status
{
    Set sc = ##class(Ens.Director).StartProduction("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Set sc = $$$OK
    Set ^InteropMCP.Config("production") = "br.musketeers.InteropMCP.Demo.Production"
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    Quit sc
}

}
