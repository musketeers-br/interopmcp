/// IRIS MCP Gateway - the queue of work the agent's inbound adapter consumes.
/// The adapter is the pull door of the agent: a producer writes the work
/// here, and the adapter - which polls - claims it and hands it to the
/// business host that runs the agent.
/// The queue carries the work item together with the context that produced
/// it: the caller's identity, the source it came from and the session it
/// belongs to. That context lives in process-private globals and does not
/// survive the boundary between the job that produced the work and the job
/// that consumes it, so it travels with the work itself.
/// The outcome of a run is not kept here: it belongs to the invocation the
/// gateway recorded, and that is where the caller collects it. What the
/// queue records is the fate of the work item - pending, claimed, done or
/// failed - so that a run that was never started is still visible.
/// Responsibilities:
/// - Accept a work item and give it an identifier.
/// - Hand each work item to exactly one consumer, even when several poll.
/// - Record the outcome of a consumed item.
/// - Fail the items whose run was abandoned, so that nothing stays claimed
///   forever.
/// The queue owns its storage and nothing else: it knows nothing about the
/// gateway's invocation store, so the adapter that consumes it stays
/// independent of how the work was produced.
Class br.musketeers.InteropMCP.Agent.Queue Extends %RegisteredObject
{

/// The lifecycle of a queued item.
Parameter StatusPending = "PENDING";

Parameter StatusProcessing = "PROCESSING";

Parameter StatusCompleted = "COMPLETED";

Parameter StatusError = "ERROR";

/// The lease of a claimed item, in seconds: how long a run may hold an item
/// before it is considered abandoned. A run that outlives its lease without
/// finishing - because the container restarted, or the job was killed - would
/// otherwise leave the item claimed forever, with nobody to release it.
Parameter DefaultLeaseSeconds = 300;

/// Accepts a work item and returns the queue identifier it was given.
/// The item carries the goal and the context that produced it; the goal is
/// the only part that is large, and it is bounded by the agent's request.
ClassMethod Enqueue(pGoal As %String, pInvocationId As %String, pAgentIdentity As %String, pSource As %String, pSessionId As %String, Output pQueueId As %String) As %Status
{
    Set sc = $$$OK
    Set pQueueId = $INCREMENT(^InteropMCP.PromptQueue.Next)

    Set entry = ##class(%DynamicObject).%New()
    Do entry.%Set("goal", pGoal)
    Do entry.%Set("invocationId", pInvocationId)
    Do entry.%Set("agentIdentity", pAgentIdentity)
    Do entry.%Set("source", pSource)
    Do entry.%Set("sessionId", pSessionId)

    Set ^InteropMCP.PromptQueue.Item(pQueueId) = entry.%ToJSON()
    Set ^InteropMCP.PromptQueue.Item(pQueueId,"status") = ..#StatusPending
    Set ^InteropMCP.PromptQueue.Item(pQueueId,"enqueuedAt") = $ZDateTime($Horolog, 3)
    // The invocation the work belongs to, so that a caller can find the item
    // again without knowing the queue identifier.
    If pInvocationId '= "" Set ^InteropMCP.PromptQueue.ByInvocation(pInvocationId) = pQueueId
    Quit sc
}

/// Hands the next pending work item to the caller and claims it, so that no
/// other consumer takes the same one. The claim is made under a lock on the
/// item, and the lock is released before the run starts: the run can take
/// minutes, and holding a lock for that long would serialise every consumer
/// on the queue.
/// The scan starts at the first item every time. A cursor would be cheaper,
/// but a cursor is shared state between consumers, and two consumers sharing
/// one would skip the work between them.
/// Outputs pEntry: the claimed item, as a dynamic object; empty when
/// nothing was pending. Outputs pQueueId: the claimed item's identifier.
ClassMethod Claim(Output pEntry As %DynamicObject, Output pQueueId As %String) As %Status
{
    Set sc = $$$OK
    Set pEntry = ""
    Set pQueueId = ""

    Set done = 0
    Set id = $O(^InteropMCP.PromptQueue.Item(0))
    While (id'="") && ('done) {
        If $Get(^InteropMCP.PromptQueue.Item(id,"status")) = ..#StatusPending {
            // The claim is made under a lock on the item's state, and the
            // lock is released before the run starts: the run can take
            // minutes, and holding the lock for that long would serialise
            // every consumer on the queue. The lock waits for a few seconds
            // at most, so that a consumer that cannot take the item moves on
            // to the next one instead of stalling the whole queue.
            Set claimed = 0
            LOCK ^InteropMCP.PromptQueue.Item(id,"status"):5
            If $TEST {
                If $Get(^InteropMCP.PromptQueue.Item(id,"status")) = ..#StatusPending {
                    Set ^InteropMCP.PromptQueue.Item(id,"status") = ..#StatusProcessing
                    Set ^InteropMCP.PromptQueue.Item(id,"claimedAt") = $ZDateTime($Horolog, 3)
                    Set claimed = 1
                }
                // The lock is released with the decrement form of the same
                // command: ObjectScript has no separate unlock command.
                LOCK -^InteropMCP.PromptQueue.Item(id,"status")
            }
            If claimed {
                Set json = $Get(^InteropMCP.PromptQueue.Item(id))
                Set parsed = ""
                If json '= "" {
                    Try {
                        Set parsed = ##class(%DynamicObject).%FromJSON(json)
                    } Catch ex {
                        Set parsed = ""
                    }
                }
                If $IsObject(parsed) {
                    Set pEntry = parsed
                    Set pQueueId = id
                    Set done = 1
                } Else {
                    // An item whose content cannot be read is failed rather
                    // than retried forever: nobody will be able to run it.
                    Do ..Complete(id, ..#StatusError, "The queued item could not be read.")
                }
            }
        }
        Set id = $O(^InteropMCP.PromptQueue.Item(id))
    }
    Quit sc
}

/// Records the outcome of a consumed item. The outcome of the run itself is
/// not kept here - it belongs to the invocation the caller polls - but the
/// fate of the item is, so that a caller that reads the queue can tell a
/// work item that is still pending from one that will never run.
ClassMethod Complete(pQueueId As %String, pStatus As %String, pErrorText As %String = "") As %Status
{
    Set sc = $$$OK
    If pQueueId = "" Quit sc
    Set ^InteropMCP.PromptQueue.Item(pQueueId,"status") = pStatus
    Set ^InteropMCP.PromptQueue.Item(pQueueId,"completedAt") = $ZDateTime($Horolog, 3)
    If pErrorText '= "" Set ^InteropMCP.PromptQueue.Item(pQueueId,"error") = pErrorText
    Quit sc
}

/// Fails the items whose run was abandoned: a claimed item whose lease has
/// expired. The run may still be alive somewhere - a slow model, a stuck
/// tool - so the item is failed rather than retried: retrying would run the
/// agent twice over the same work.
/// Outputs pAbandoned: the identifiers of the items that were failed.
ClassMethod Reap(pLeaseSeconds As %Integer, Output pAbandoned As %DynamicArray) As %Status
{
    Set sc = $$$OK
    Set pAbandoned = ##class(%DynamicArray).%New()
    If pLeaseSeconds <= 0 Set pLeaseSeconds = ..#DefaultLeaseSeconds
    Set cutoff = $ZDateTime($Horolog - pLeaseSeconds, 3)

    Set id = $O(^InteropMCP.PromptQueue.Item(0))
    While (id'="") {
        If $Get(^InteropMCP.PromptQueue.Item(id,"status")) = ..#StatusProcessing {
            Set claimedAt = $Get(^InteropMCP.PromptQueue.Item(id,"claimedAt"))
            If (claimedAt'="") && (claimedAt < cutoff) {
                Set reason = "The run was abandoned: it held the work item for more than "_pLeaseSeconds_" seconds."
                Do ..Complete(id, ..#StatusError, reason)
                Do pAbandoned.%Push(id)
            }
        }
        Set id = $O(^InteropMCP.PromptQueue.Item(id))
    }
    Quit sc
}

/// Returns the identifier of the item that belongs to an invocation, and the
/// item's state. Used by the caller that waits for a run: it tells a work
/// item that is still waiting from one that will never run.
ClassMethod ByInvocation(pInvocationId As %String, Output pQueueId As %String, Output pStatus As %String, Output pErrorText As %String) As %Status
{
    Set sc = $$$OK
    Set pQueueId = ""
    Set pStatus = ""
    Set pErrorText = ""
    If pInvocationId = "" Quit sc
    Set pQueueId = $Get(^InteropMCP.PromptQueue.ByInvocation(pInvocationId))
    If pQueueId = "" Quit sc
    Set pStatus = $Get(^InteropMCP.PromptQueue.Item(pQueueId,"status"))
    Set pErrorText = $Get(^InteropMCP.PromptQueue.Item(pQueueId,"error"))
    Quit sc
}

/// Returns the state of one item, for an operator reading the queue.
ClassMethod Status(pQueueId As %String, Output pStatus As %String) As %Status
{
    Set sc = $$$OK
    Set pStatus = ""
    If pQueueId = "" Quit sc
    Set pStatus = $Get(^InteropMCP.PromptQueue.Item(pQueueId,"status"))
    Quit sc
}

}
