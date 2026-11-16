/// Exercises the queue of work the agent's inbound adapter consumes.
/// The queue is the adapter's input: a work item is accepted, claimed by
/// exactly one consumer, completed, and swept when the run that held it was
/// abandoned.
///
/// Usage:
///   Do ##class(br.musketeers.InteropMCP.TestAgentQueue).Run()
Class br.musketeers.InteropMCP.TestAgentQueue Extends %RegisteredObject
{

/// The queue the test writes into. It is the same queue the adapter reads.
Parameter Queue = "^InteropMCP.PromptQueue";

/// The goal the test queues. It has to be recognisable, so that a claim
/// that returns something else is caught.
Parameter TestGoal = "Assess the supplier named in the attached invoice.";

/// The identity the test queues with, to prove that the context travels
/// with the work.
Parameter TestIdentity = "mcp_demo";

/// Runs the exercise and writes what happened to the console. The class
/// method's status is the status of the run: an error when a check failed.
ClassMethod Run() As %Status
{
    Set sc = $$$OK
    Set failures = 0
    Do ..WriteLog("=== AGENT QUEUE ===")
    Do ..WriteLog("Date: "_$ZDateTime($Horolog, 3))
    Do ..WriteLog("")

    // 1. A work item is accepted and given an identifier.
    Set queueId = ""
    Set enqSc = ##class(br.musketeers.InteropMCP.Agent.Queue).Enqueue(..#TestGoal, "TEST-INVOCATION", ..#TestIdentity, "REST", "0", .queueId)
    If $$$ISERR(enqSc) {
        Do ..WriteLog("FAIL  enqueue: "_$SYSTEM.Status.GetErrorText(enqSc))
        Set failures = failures + 1
    } Else {
        Do ..WriteLog("OK    enqueued item "_queueId)
        If $Get(^InteropMCP.PromptQueue.Item(queueId,"status")) '= "PENDING" {
            Do ..WriteLog("FAIL  the accepted item is not pending")
            Set failures = failures + 1
        }
    }

    // 2. It is claimed, with the context that produced it.
    Set entry = ""
    Set claimedId = ""
    Set claimSc = ##class(br.musketeers.InteropMCP.Agent.Queue).Claim(.entry, .claimedId)
    If $$$ISERR(claimSc) {
        Do ..WriteLog("FAIL  claim: "_$SYSTEM.Status.GetErrorText(claimSc))
        Set failures = failures + 1
    } ElseIf '$IsObject(entry) {
        Do ..WriteLog("FAIL  nothing was claimed")
        Set failures = failures + 1
    } Else {
        Do ..WriteLog("OK    claimed item "_claimedId)
        If entry.%Get("goal") '= ..#TestGoal {
            Do ..WriteLog("FAIL  the claimed item carries another goal")
            Set failures = failures + 1
        }
        If entry.%Get("agentIdentity") '= ..#TestIdentity {
            Do ..WriteLog("FAIL  the claimed item lost the caller's identity")
            Set failures = failures + 1
        }
        If $Get(^InteropMCP.PromptQueue.Item(claimedId,"status")) '= "PROCESSING" {
            Do ..WriteLog("FAIL  the claimed item is not marked as being processed")
            Set failures = failures + 1
        }
    }

    // 3. A second consumer finds nothing: the item was taken.
    Set secondEntry = ""
    Set secondId = ""
    Set secondSc = ##class(br.musketeers.InteropMCP.Agent.Queue).Claim(.secondEntry, .secondId)
    If $$$ISERR(secondSc) {
        Do ..WriteLog("FAIL  second claim: "_$SYSTEM.Status.GetErrorText(secondSc))
        Set failures = failures + 1
    } ElseIf $IsObject(secondEntry) {
        Do ..WriteLog("FAIL  a claimed item was handed to a second consumer")
        Set failures = failures + 1
    } Else {
        Do ..WriteLog("OK    a second consumer found nothing to take")
    }

    // 4. The item can be found again by the invocation it belongs to.
    Set foundId = ""
    Set foundStatus = ""
    Set foundError = ""
    Set byInvSc = ##class(br.musketeers.InteropMCP.Agent.Queue).ByInvocation("TEST-INVOCATION", .foundId, .foundStatus, .foundError)
    If $$$ISERR(byInvSc) {
        Do ..WriteLog("FAIL  lookup by invocation: "_$SYSTEM.Status.GetErrorText(byInvSc))
        Set failures = failures + 1
    } ElseIf foundId '= claimedId {
        Do ..WriteLog("FAIL  the item was not found by its invocation")
        Set failures = failures + 1
    } Else {
        Do ..WriteLog("OK    the item is found by its invocation")
    }

    // 5. A run that was abandoned is swept: the item is failed rather than
    // left claimed forever.
    If claimedId '= "" {
        Set ^InteropMCP.PromptQueue.Item(claimedId,"claimedAt") = $ZDateTime($Horolog - 600, 3)
        Set abandoned = ##class(%DynamicArray).%New()
        Set reapSc = ##class(br.musketeers.InteropMCP.Agent.Queue).Reap(300, .abandoned)
        If $$$ISERR(reapSc) {
            Do ..WriteLog("FAIL  reap: "_$SYSTEM.Status.GetErrorText(reapSc))
            Set failures = failures + 1
        } ElseIf abandoned.size() = 0 {
            Do ..WriteLog("FAIL  an abandoned item was not swept")
            Set failures = failures + 1
        } Else {
            Do ..WriteLog("OK    the abandoned item was swept")
            If $Get(^InteropMCP.PromptQueue.Item(claimedId,"status")) '= "ERROR" {
                Do ..WriteLog("FAIL  the abandoned item was not failed")
                Set failures = failures + 1
            }
        }
    }

    // 6. A completed item keeps its outcome.
    Set doneId = ""
    Set doneSc = ##class(br.musketeers.InteropMCP.Agent.Queue).Enqueue("A second work item.", "TEST-INVOCATION-2", ..#TestIdentity, "REST", "0", .doneId)
    If $$$ISERR(doneSc) {
        Do ..WriteLog("FAIL  enqueue: "_$SYSTEM.Status.GetErrorText(doneSc))
        Set failures = failures + 1
    } Else {
        Set doneEntry = ""
        Set doneClaimed = ""
        Do ##class(br.musketeers.InteropMCP.Agent.Queue).Claim(.doneEntry, .doneClaimed)
        Do ##class(br.musketeers.InteropMCP.Agent.Queue).Complete(doneClaimed, "COMPLETED", "")
        If $Get(^InteropMCP.PromptQueue.Item(doneClaimed,"status")) '= "COMPLETED" {
            Do ..WriteLog("FAIL  the completed item did not keep its outcome")
            Set failures = failures + 1
        } Else {
            Do ..WriteLog("OK    a completed item keeps its outcome")
        }
    }

    // The test leaves the queue as it found it.
    If claimedId '= "" Do ..Purge(claimedId)
    If doneId '= "" Do ..Purge(doneId)
    Kill ^InteropMCP.PromptQueue.ByInvocation("TEST-INVOCATION")
    Kill ^InteropMCP.PromptQueue.ByInvocation("TEST-INVOCATION-2")

    Do ..WriteLog("")
    If failures = 0 {
        Do ..WriteLog("RESULT: all checks passed.")
    } Else {
        Do ..WriteLog("RESULT: "_failures_" check(s) failed.")
        Set sc = $$$ERROR($$$GeneralError, failures_" queue check(s) failed.")
    }
    Quit sc
}

/// Removes one item from the queue, so that a test run leaves no trace.
ClassMethod Purge(pQueueId As %String) As %Status
{
    If pQueueId = "" Quit $$$OK
    Kill ^InteropMCP.PromptQueue.Item(pQueueId)
    Quit $$$OK
}

/// Writes one line to the console.
ClassMethod WriteLog(pMessage As %String) As %Status
{
    Write pMessage, !
    Quit $$$OK
}

}
