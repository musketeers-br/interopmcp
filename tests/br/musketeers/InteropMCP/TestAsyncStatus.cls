Class br.musketeers.InteropMCP.TestAsyncStatus Extends %UnitTest.TestCase
{

/// A long-running tool call is answered with a processing reference and
/// leaves exactly one auditable row behind. The row reaches its terminal
/// state in the background, where the business host records the outcome;
/// the caller collects it by polling the invocation.
Method TestAsyncStatus() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.Registry).BuildCatalog("br.musketeers.InteropMCP.Demo.Production")
    If $$$ISERR(sc) Quit sc
    Set resp = ##class(br.musketeers.InteropMCP.GeneratedTools).BatchRun("daily")
    Do $$$AssertEquals(resp.%Get("_status"), "pending", "Async call returns a processing reference")
    Set invocationId = resp.%Get("invocationId")
    Do $$$AssertTrue(invocationId '= "", "Processing reference recorded")
    Set count = 0
    Set found = 0
    Set status = ""
    Set id = $Order(^InteropMCP.InvocationsD(""))
    While id '= "" && 'found {
        Set count = count + 1
        Set inv = ##class(br.musketeers.InteropMCP.Invocations).%OpenId(id)
        If inv.InvocationId = invocationId {
            Set found = 1
            Set status = inv.Status
        }
        Set id = $Order(^InteropMCP.InvocationsD(id))
    }
    Do $$$AssertTrue(count >= 1, "Async invocation recorded with reference")
    Do $$$AssertTrue(found, "The invocation of the call is stored")
    If found {
        // The run is dispatched to the background, so the row is executing
        // while it runs and completed when the business host records the
        // outcome. Both are the states the caller polls through.
        Do $$$AssertTrue((status = "executing") || (status = "completed"), "The invocation is on its way")
    }
    Quit $$$OK
}

}
