/// IRIS MCP Gateway - workflow prerequisites bootstrap.
/// Creates the Operators role, a dedicated workflow user and membership.
/// Also enables IRIS BI (DeepSee) User Portal for the namespace CSP app.
/// Idempotent: re-running is safe.
/// Called automatically by br.musketeers.InteropMCP.Setup.Run.
Class br.musketeers.InteropMCP.Workflow.Setup Extends %RegisteredObject
{

Parameter RoleName = "Operators";
Parameter UserName = "interopec_user";
Parameter UserPassword = "InteropMCP_Workflow_2026!";
Parameter FullName = "Interop MCP Workflow Operator";
Parameter SystemUserName = "_SYSTEM";

/// Ensures workflow prerequisites: role, user, membership, DeepSee portal, workflow engine objects.
ClassMethod EnsurePrerequisites() As %Status
{
    Set sc = ..EnsureRole()
    If $$$ISERR(sc) Quit sc
    Set sc = ..EnsureUser()
    If $$$ISERR(sc) Quit sc
    Set sc = ..EnsureMembership()
    If $$$ISERR(sc) Quit sc
    Set sc = ..EnsureDeepSeePortal()
    If $$$ISERR(sc) Quit sc
    Set sc = ..EnsureWorkflowEngineObjects()
    If $$$ISERR(sc) Quit sc
    Quit $$$OK
}

/// Idempotent role creation.
ClassMethod EnsureRole() As %Status
{
    Set oldNs = $Namespace
    Set $NAMESPACE = "%SYS"
    Set sc = $$$OK
    If '##class(Security.Roles).Exists(..#RoleName) {
        Set sc = ##class(Security.Roles).Create(..#RoleName, "Interop MCP Workflow Operators", "", "", 0)
    }
    Set $NAMESPACE = oldNs
    Quit sc
}

/// Ensures the workflow user exists with a valid password and is enabled.
/// Uses the property-array API because Security.Users.Create rejects
/// an empty expiration date on this IRIS build.
ClassMethod EnsureUser() As %Status
{
    Set oldNs = $Namespace
    Set $NAMESPACE = "%SYS"
    Set sc = $$$OK
    If '##class(Security.Users).Exists(..#UserName) {
        Kill props
        Set props("Name") = ..#UserName
        Set props("Username") = ..#UserName
        Set props("Password") = ..#UserPassword
        Set props("FullName") = ..#FullName
        Set props("Enabled") = 1
        Set props("AccountNeverExpires") = 1
        Set props("PasswordNeverExpires") = 1
        Set sc = ##class(Security.Users).CreateOne(.props)
        If $$$ISERR(sc) {
            Set $NAMESPACE = oldNs
            Quit sc
        }
    } Else {
        // Reconcile existing user: ensure enabled and non-expiring
        Kill props
        Set sc = ##class(Security.Users).Get(..#UserName, .props)
        If $$$ISERR(sc) {
            Set $NAMESPACE = oldNs
            Quit sc
        }
        Set props("Enabled") = 1
        Set props("AccountNeverExpires") = 1
        Set props("PasswordNeverExpires") = 1
        Set sc = ##class(Security.Users).Modify(..#UserName, .props)
        If $$$ISERR(sc) {
            Set $NAMESPACE = oldNs
            Quit sc
        }
    }
    Set $NAMESPACE = oldNs
    Quit sc
}

/// Ensures user belongs to the Operators role.
ClassMethod EnsureMembership() As %Status
{
    Set oldNs = $Namespace
    Set $NAMESPACE = "%SYS"
    Set sc = $$$OK
    If ##class(Security.Users).Exists(..#UserName) && ##class(Security.Roles).Exists(..#RoleName) {
        Kill props
        Set sc = ##class(Security.Users).Get(..#UserName, .props)
        If $$$ISERR(sc) {
            Set $NAMESPACE = oldNs
            Quit sc
        }
        Set props("Enabled") = 1
        Set existingRoles = $Get(props("Roles"))
        Set rolesList = ..#RoleName
        If existingRoles '= "" {
            // Check if role already exists
            If existingRoles '[ ..#RoleName {
                Set rolesList = existingRoles_","_..#RoleName
            }
        }
        Set props("Roles") = rolesList
        Set sc = ##class(Security.Users).Modify(..#UserName, .props)
        If $$$ISERR(sc) {
            Set $NAMESPACE = oldNs
            Quit sc
        }
    }
    Set $NAMESPACE = oldNs
    Quit sc
}

/// Enables IRIS BI (DeepSee) User Portal for the namespace CSP application.
/// Grants %DeepSee.* class access, enables DeepSee on the CSP app,
/// and grants required resources to the Operators role.
ClassMethod EnsureDeepSeePortal() As %Status
{
    Set sc = $$$OK
    Set oldNs = $Namespace
    Set cspNs = oldNs   ; namespace whose CSP app we configure
    Set $NAMESPACE = "%SYS"
    Set didEnable = 0
    Try {
        // 1. Enable DeepSee on the namespace CSP application
        Set appPath = "/csp/"_$ZCONVERT(cspNs,"L")
        Kill props
        Set props("DeepSeeEnabled") = 1
        Set sc = ##class(Security.Applications).Modify(appPath, .props)
        If $$$ISERR(sc) {
            // Application may not exist yet during build; try to create it
            Kill props
            Set props("Name") = appPath
            Set props("NameSpace") = cspNs
            Set props("Enabled") = 1
            Set props("Type") = 2
            Set props("CSPZENEnabled") = 1
            Set sc = ##class(Security.Applications).Create(appPath, .props)
            If $$$ISERR(sc) {
                Do ..LogWarning("Create CSP app "_appPath_" failed: "_$System.Status.GetErrorText(sc))
                Set sc = $$$OK
            } Else {
                // Now try to enable DeepSee
                Kill props
                Set props("DeepSeeEnabled") = 1
                Set sc = ##class(Security.Applications).Modify(appPath, .props)
                If $$$ISERR(sc) {
                    Do ..LogWarning("DeepSee enable on app "_appPath_" failed: "_$System.Status.GetErrorText(sc))
                    Set sc = $$$OK
                } Else {
                    Set didEnable = 1
                }
            }
        } Else {
            Set didEnable = 1
        }

        // 2. Allow %DeepSee.* classes on the CSP application path
        If didEnable {
            Set sc = ..AllowDeepSeeClasses(appPath)
            If $$$ISERR(sc) {
                Do ..LogWarning("Allow %DeepSee.* classes failed: "_$System.Status.GetErrorText(sc))
                Set sc = $$$OK
            }

            // 3. Grant DeepSee resources to Operators role
            Set sc = ..GrantDeepSeeResources()
            If $$$ISERR(sc) {
                Do ..LogWarning("Grant DeepSee resources failed: "_$System.Status.GetErrorText(sc))
                Set sc = $$$OK
            }
        }

    } Catch ex {
        Do ..LogWarning("DeepSee portal setup failed: "_ex.DisplayString())
    }
    Set $NAMESPACE = oldNs
    Quit $$$OK
}

/// Allows %DeepSee.* class prefix on the given CSP application path.
ClassMethod AllowDeepSeeClasses(pAppPath As %String) As %Status
{
    Set sc = $$$OK
    Try {
        Set exists = ##class(Security.WebAppPctAccess).Exists(pAppPath, "AllowPrefix", "%DeepSee.")
        If 'exists {
            Kill props
            Set props("AllowAccess") = 1
            Set sc = ##class(Security.WebAppPctAccess).Create(pAppPath, "AllowPrefix", "%DeepSee.", .props)
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Grants DeepSee and Workflow resources to the Operators role.
ClassMethod GrantDeepSeeResources() As %Status
{
    Set sc = $$$OK
    Try {
        Kill props
        Set props("Resources") = "%Ens_Portal:U,%DeepSee_Portal:U,%DeepSee_PortalEdit:U,%DeepSee_Analyzer:U,%DeepSee_Architect:U,%Ens_WorkflowConfig:U"
        Set sc = ##class(Security.Roles).Modify(..#RoleName, .props)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Creates the Workflow Engine objects: RoleDefinition, UserDefinition, RoleMembership.
/// Creates entries for both the dedicated workflow user and _SYSTEM so both appear
/// in the IRIS BI User Portal workflow task list.
ClassMethod EnsureWorkflowEngineObjects() As %Status
{
    Set sc = $$$OK
    Set oldNs = $Namespace
    Set $NAMESPACE = "IRISAPP"
    Try {
        // RoleDefinition "Operators"
        Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(..#RoleName)
        If '$IsObject(role) {
            Set role = ##class(EnsLib.Workflow.RoleDefinition).%New()
            Set role.Name = ..#RoleName
            Set role.Description = "Interop MCP Workflow Operators"
            Set role.Capacity = 10
            Set sc = role.%Save()
            If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
        }

        // UserDefinition for workflow user (interopec_user)
        If $$$ISOK(sc) {
            Set user = ##class(EnsLib.Workflow.UserDefinition).%OpenId(..#UserName)
            If '$IsObject(user) {
                Set user = ##class(EnsLib.Workflow.UserDefinition).%New()
                Set user.Name = ..#UserName
                Set user.FullName = ..#FullName
                Set user.IsActive = 1
                Set sc = user.%Save()
            }
        }

        // UserDefinition for system user (_SYSTEM)
        If $$$ISOK(sc) {
            Set sysUser = ##class(EnsLib.Workflow.UserDefinition).%OpenId(..#SystemUserName)
            If '$IsObject(sysUser) {
                Set sysUser = ##class(EnsLib.Workflow.UserDefinition).%New()
                Set sysUser.Name = ..#SystemUserName
                Set sysUser.FullName = "System User"
                Set sysUser.IsActive = 1
                Set sc = sysUser.%Save()
            }
        }

        // RoleMembership for both users
        If $$$ISOK(sc) {
            Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(..#RoleName)
            If $IsObject(role) {
                // interopec_user membership
                Set user = ##class(EnsLib.Workflow.UserDefinition).%OpenId(..#UserName)
                If $IsObject(user) {
                    If '$Data(^EnsLib.W.RoleMembershipD(..#RoleName,..#UserName)) {
                        Set m = ##class(EnsLib.Workflow.RoleMembership).%New()
                        Set m.Role = role
                        Set m.User = user
                        Set m.Title = "Operator"
                        Set m.Ranking = 1
                        Set sc = m.%Save()
                    }
                }
            }
        }

        If $$$ISOK(sc) {
            Set role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(..#RoleName)
            If $IsObject(role) {
                Set sysUser = ##class(EnsLib.Workflow.UserDefinition).%OpenId(..#SystemUserName)
                If $IsObject(sysUser) {
                    If '$Data(^EnsLib.W.RoleMembershipD(..#RoleName,..#SystemUserName)) {
                        Set m = ##class(EnsLib.Workflow.RoleMembership).%New()
                        Set m.Role = role
                        Set m.User = sysUser
                        Set m.Title = "Operator"
                        Set m.Ranking = 1
                        Set sc = m.%Save()
                    }
                }
            }
        }

    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Set $NAMESPACE = oldNs
    Quit sc
}

/// Helper to log warnings without failing the setup.
ClassMethod LogWarning(pMessage As %String) As %Status
{
    Write !,"[Workflow.Setup] ",pMessage
    Quit $$$OK
}

}