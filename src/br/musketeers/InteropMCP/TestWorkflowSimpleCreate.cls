/// Simple example: creating a workflow task.
/// Based on TestWorkflowErrorSimulation.cls, starting from the basics.
///
/// Usage:
///   Do ##class(br.musketeers.InteropMCP.TestWorkflowSimpleCreate).Run()
Class br.musketeers.InteropMCP.TestWorkflowSimpleCreate Extends %RegisteredObject
{

/// Name of the workflow role used to list the task in the user portal.
Parameter RoleName = "SimpleOperators";

/// Main method: creates the workflow task and shows the ID.
ClassMethod Run() As %Status
{
    Set sc = $$$OK
    Try {
        Do ..WriteLog("=== SIMPLE WORKFLOW TASK CREATION ===")
        Do ..WriteLog("Date: "_$ZDateTime($Horolog, 3))
        Do ..WriteLog("")

        // 1. Ensure the role exists (minimum needed for the portal to list)
        Do ..EnsureRole(.sc)
        If $$$ISERR(sc) { Return sc }

        // 2. Ensure _SYSTEM user is associated with the role (so the task
        //    assigned via SendTaskToAll reaches _SYSTEM's worklist)
        Do ..EnsureUserInRole(.sc)
        If $$$ISERR(sc) { Return sc }

        // 3. Create only the task
        Set taskId = ""
        Do ..CreateWorkflowTask(.sc, .taskId)
        If $$$ISERR(sc) { Return sc }

        Do ..WriteLog("")
        Do ..WriteLog("=== DONE ===")
        Do ..WriteLog("Task ID: "_taskId)

    } Catch ex {
        Return ex.AsStatus()
    }
    Return $$$OK
}

/// Ensures the workflow role exists.
ClassMethod EnsureRole(ByRef sc As %Status)
{
    Try {
        Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(..#RoleName)
        If $IsObject(role) {
            Do ..WriteLog("OK: Role '"_..#RoleName_"' already exists")
            Set sc = $$$OK
            Return
        }

        Set role = ##class(EnsLib.Workflow.RoleDefinition).%New()
        Set role.Name = ..#RoleName
        Set role.Description = "Simple role for task creation"
        Set role.Capacity = 10
        Set sc = role.%Save()
        If $$$ISERR(sc) {
            Do ..WriteLog("ERROR creating role: "_$System.Status.GetErrorText(sc))
            Return sc
        }
        Do ..WriteLog("OK: Role '"_..#RoleName_"' created")
    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("ERROR: "_ex.DisplayString())
    }
    Quit sc
}

/// Ensures _SYSTEM user exists as UserDefinition and is a member of the role.
ClassMethod EnsureUserInRole(ByRef sc As %Status)
{
    Try {
        // Ensure _SYSTEM UserDefinition exists
        Set user = ##class(EnsLib.Workflow.UserDefinition).%OpenId("_SYSTEM")
        If '$IsObject(user) {
            Set user = ##class(EnsLib.Workflow.UserDefinition).%New()
            Set user.Name = "_SYSTEM"
            Set user.FullName = "System User"
            Set user.IsActive = 1
            Set sc = user.%Save()
            If $$$ISERR(sc) {
                Do ..WriteLog("ERROR creating _SYSTEM UserDefinition: "_$System.Status.GetErrorText(sc))
                Return sc
            }
            Do ..WriteLog("OK: User _SYSTEM created as UserDefinition")
        } Else {
            Do ..WriteLog("OK: User _SYSTEM already exists as UserDefinition")
        }

        // Ensure role exists
        Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(..#RoleName)
        If '$IsObject(role) {
            Set sc = $$$ERROR($$$GeneralError, "Role '"_..#RoleName_"' not found")
            Return sc
        }

        // Check if membership already exists via global
        If $Data(^EnsLib.W.RoleMembershipD(..#RoleName,"_SYSTEM")) {
            Do ..WriteLog("OK: _SYSTEM already associated with role '"_..#RoleName_"'")
            Set sc = $$$OK
            Return
        }

        Set tMember = ##class(EnsLib.Workflow.RoleMembership).%New()
        Set tMember.Role = role
        Set tMember.User = user
        Set tMember.Title = "Operator"
        Set tMember.Ranking = 1
        Set sc = tMember.%Save()
        If $$$ISERR(sc) {
            Do ..WriteLog("ERROR associating user with role: "_$System.Status.GetErrorText(sc))
            Return sc
        }
        Do ..WriteLog("OK: _SYSTEM associated with role '"_..#RoleName_"'")
    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("ERROR: "_ex.DisplayString())
    }
    Quit sc
}

/// Creates only the workflow task (no error reproduction, no DeepSee, no production).
/// Minimal recipe:
///   1. request.NewResponse(.response) creates the TaskResponse
///   2. response.%TaskStatus.Request = request   (required)
///   3. response.%TaskStatus.Role = role         (needed for the portal to list)
///   4. response.%Save()
///   5. Engine.SendTaskToAll(response,.count)    (populates the Inbox Worklist)
ClassMethod CreateWorkflowTask(ByRef sc As %Status, Output pTaskId As %String)
{
    Set pTaskId = ""
    Set sc = $$$OK
    Try {
        Set request = ##class(EnsLib.Workflow.TaskRequest).%New()
        Set request.%Subject = "Simple task test"
        Set request.%Message = "Task created by the simple example"
        Set request.%Priority = 1
        Set request.%Actions = "Approve,Reject"

        Set response = ""
        Set sc = request.NewResponse(.response)
        If $$$ISERR(sc) {
            Do ..WriteLog("ERROR creating response: "_$System.Status.GetErrorText(sc))
            Return sc
        }

        Set response.%TaskStatus.Request = request

        // Copy fields from request to response (what %DistributeTask would do)
        Set response.%Priority = request.%Priority
        Set response.%Subject = request.%Subject
        Set response.%Message = request.%Message
        Set response.%Actions = request.%Actions

        Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(..#RoleName)
        If $IsObject(role) {
            Set response.%TaskStatus.Role = role
        }
        Set response.%TaskStatus.IsComplete = 0

        Set sc = response.%Save()
        If $$$ISERR(sc) {
            Do ..WriteLog("ERROR saving task: "_$System.Status.GetErrorText(sc))
            Return sc
        }

        Set pTaskId = response.%Id()
        Do ..WriteLog("OK: Task created with ID: "_pTaskId)

        // Populate the Worklist for role members (what the portal lists)
        Set count = 0
        Set distSc = ##class(EnsLib.Workflow.Engine).SendTaskToAll(response, .count)
        If $$$ISERR(distSc) {
            Do ..WriteLog("WARNING populating worklist: "_$System.Status.GetErrorText(distSc))
        } Else {
            Do ..WriteLog("OK: Task sent to "_count_" user(s)")
        }

    } Catch ex {
        Set sc = ex.AsStatus()
        Do ..WriteLog("ERROR: "_ex.DisplayString())
    }
    Quit sc
}

/// Writes a message to the terminal.
ClassMethod WriteLog(pMessage As %String)
{
    Write pMessage, !
    Return $$$OK
}

}
