/// IRIS MCP Gateway - per-run audit of the agent's tool calls.
/// The policy records every execution and denial in the order the agent made
/// them. It deliberately does not read the invocation store: the host hydrates
/// each entry with the authoritative lifecycle row after the run, so a held or
/// failed call is reported with the same shape as a completed one.
Class br.musketeers.InteropMCP.Agent.ToolAudit Extends %AI.Policy.Audit
{

/// Calls observed during one agent run, in execution order.
Property Calls As %DynamicArray;

Method %OnNew() As %Status
{
    Set ..Calls = ##class(%DynamicArray).%New()
    Quit $$$OK
}

/// Records one executed tool call. The result is kept as the tool manager
/// rendered it; the host resolves the invocation id from it afterwards.
Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
    Set toolName = ""
    Set arguments = ""
    Try {
        Set toolName = ##class(%AI.Utils.Text).StripControlChars(call.name)
        Set arguments = call.arguments
    } Catch ex {
        Set toolName = ""
        Set arguments = ""
    }

    Set resultJson = ""
    Try {
        If $IsObject(result) {
            If result."display_text" '= "" Set resultJson = result."display_text"
            If result."result_json" '= "" Set resultJson = result."result_json"
            Set resultJson = ##class(%AI.Utils.Text).StripControlChars(resultJson)
        }
    } Catch ex {
        Set resultJson = ""
    }

    Set entry = {}
    Do entry.%Set("tool", toolName)
    Do entry.%Set("arguments", arguments)
    Do entry.%Set("durationMs", +$Get(duration, 0))
    Do entry.%Set("ok", $$$ISOK(status))
    Do entry.%Set("resultJson", resultJson)
    Do ..Calls.%Push(entry)
    Quit $$$OK
}

/// Records a call the policy refused before it reached a tool.
Method %LogDenial(call As %DynamicObject, metadata As %DynamicObject, status As %Status) As %Status
{
    Set toolName = ""
    Set arguments = ""
    Try {
        Set toolName = ##class(%AI.Utils.Text).StripControlChars(call.name)
        Set arguments = call.arguments
    } Catch ex {
        Set toolName = ""
        Set arguments = ""
    }

    Set entry = {}
    Do entry.%Set("tool", toolName)
    Do entry.%Set("arguments", arguments)
    Do entry.%Set("durationMs", 0)
    Do entry.%Set("ok", 0)
    Do entry.%Set("status", "denied")
    Do entry.%Set("error", $System.Status.GetErrorText(status))
    Do ..Calls.%Push(entry)
    Quit $$$OK
}

}
