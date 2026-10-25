/// IRIS MCP Gateway - leveled structured logging.
/// Every gateway component (registry, guardrail, invoker, approval, mcp)
/// emits its operational events through this helper so log format, level
/// gating and persistence stay consistent across layers.
/// Output sinks:
/// - Persistent: one line per event in the global ^InteropMCP.LogD
///   (incremented integer id), query-friendly for audit and operations
/// - Console: the same line written to the current device (visible in
///   terminal sessions and container logs)
/// Level gating: events below the MinLevel parameter are silently dropped
/// (debug is the most verbose, error the most severe).
Class br.musketeers.InteropMCP.Log Extends %RegisteredObject
{

/// Minimum level actually emitted. Events with a lower rank are dropped.
/// Rank order: debug (0), info (1), warn (2), error (3).
Parameter MinLevel = "info";

/// Maps a level name to its severity rank. Unknown levels rank as info so a
/// mistyped level is never silently promoted to error severity.
ClassMethod Rank(pLevel As %String) As %Integer
{
    Set pLevel = $ZConvert(pLevel, "L")
    If pLevel = "debug" Quit 0
    If pLevel = "info" Quit 1
    If pLevel = "warn" Quit 2
    If pLevel = "error" Quit 3
    Quit 1
}

/// Writes one log event. pLevel is one of debug, info, warn, error;
/// pComponent tags the emitting layer (registry, guardrail, invoker,
/// approval, mcp); pData is an optional dynamic object serialized into the
/// line as structured context. The line is appended to ^InteropMCP.LogD and
/// written to the current device.
ClassMethod Write(pLevel As %String, pComponent As %String, pMessage As %String, pData As %DynamicObject = "") As %Status
{
    Set level = $ZConvert(pLevel, "L")
    Set minLevel = $ZConvert(..#MinLevel, "L")
    If ..Rank(level) < ..Rank(minLevel) Quit $$$OK
    Set ts = $ZDateTime($Horolog, 3)
    Set line = ts _ " | " _ $ZConvert(level, "U") _ " | " _ pComponent _ " | " _ pMessage
    If $IsObject(pData) Set line = line _ " | " _ pData.%ToJSON()
    Set tId = $Increment(^InteropMCP.LogD)
    Set ^InteropMCP.LogD(tId) = line
    Write line, !
    Quit $$$OK
}

}
