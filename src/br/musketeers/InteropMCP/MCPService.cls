/// IRIS MCP Gateway - MCP protocol dispatcher.
/// AI HUB MCP service bound to the gateway toolset. A web application of
/// Type 18 (MCP service) at path /mcp/interopmcp dispatches incoming MCP
/// JSON-RPC traffic into this class, which resolves the toolset declared in
/// the SPECIFICATION parameter (br.musketeers.InteropMCP.ToolSet) and exposes its included
/// tools to connected agents.
/// Provisioned by br.musketeers.InteropMCP.Setup (dev or prod authentication posture);
/// this class holds no business logic of its own.
Class br.musketeers.InteropMCP.MCPService Extends %AI.MCP.Service
{

/// Toolset specification consumed by the AI HUB MCP layer: every tool
/// included in br.musketeers.InteropMCP.ToolSet becomes callable through this service.
Parameter SPECIFICATION = "br.musketeers.InteropMCP.ToolSet";

/// IRIS security resource required for every REST and WebSocket request.
/// Setup creates this resource and grants it to InteropMCPRoles. Keeping the
/// check here, rather than on the web application, lets the gateway return a
/// JSON 403 and write its own audit record instead of letting the CSP
/// dispatcher reject the request before MCPService is reached.
Parameter RESOURCE = "InteropMCP_Access";

/// Returns the username claim from a Basic Authorization header, or the empty
/// string when the header is absent, malformed, or not Basic. The password and
/// the encoded token are discarded.
ClassMethod UsernameClaim() As %String
{
    Quit ..UsernameFromHeader($Get(%request.CgiEnvs("HTTP_AUTHORIZATION")))
}

/// Extracts the username from a raw Authorization header value. Returns the
/// empty string when the header is absent, is not Basic, or carries no
/// username. Only the username part is returned - the password and the
/// encoded token are never exposed to the caller.
ClassMethod UsernameFromHeader(pHeader As %String) As %String
{
    If pHeader = "" Quit ""
    If $ZConvert($Piece(pHeader, " ", 1), "L") '= "basic" Quit ""
    Set encoded = $Piece(pHeader, " ", 2)
    If encoded = "" Quit ""
    Set decoded = ""
    Try {
        Set decoded = $System.Encryption.Base64Decode(encoded)
    } Catch ex {
        Set decoded = ""
    }
    If decoded = "" Quit ""
    Quit $Piece(decoded, ":", 1)
}

/// Writes one platform audit record for an authentication or entitlement
/// denial. Never includes the Authorization header, the Basic token, or the
/// password. Audit failures are logged best-effort and do not change the
/// caller's HTTP response.
ClassMethod RecordAccessDecision(pOutcome As %String, pReason As %String = "", pUsername As %String = "") As %Status
{
    Set event = $Select(pOutcome = "entitlement-denied": "AccessDenied", 1: "AuthenticationDenied")
    Set endpoint = ""
    Try {
        Set endpoint = $Get(%request.URL)
    } Catch ex {
        Set endpoint = ""
    }
    If endpoint = "" {
        Try {
            Set endpoint = $Get(%request.CgiEnvs("REQUEST_URI"))
        } Catch ex {
            Set endpoint = ""
        }
    }
    If endpoint = "" Set endpoint = "unknown"
    Set user = pUsername
    If user = "" Set user = $USERNAME
    Set data = "user="_user_";endpoint="_endpoint_";outcome="_pOutcome
    If pReason '= "" Set data = data_";reason="_pReason
    Try {
        Do ##class(%SYS.Audit).WriteToAuditFile("InteropMCP", "INTEROPMCP", event, data, "InteropMCP access decision", 1)
    } Catch ex {
        Set logData = ##class(%DynamicObject).%New()
        Do logData.%Set("outcome", pOutcome)
        Do logData.%Set("reason", pReason)
        Do ##class(br.musketeers.InteropMCP.Log).Write("error", "mcp", "Access decision audit failed", logData)
    }
    Quit $$$OK
}

/// Enforces the class-level RESOURCE parameter after CSP authentication has
/// established $USERNAME and $ROLES. A caller without USE access is recorded
/// in the gateway audit trail and then left to the base class, which turns
/// the unauthorized flag into the JSON 403 response. Returning an error
/// status here would make the base class answer 500 instead.
ClassMethod AccessCheck(Output pAuthorized As %Boolean = 0) As %Status
{
    Set sc = ##super(.pAuthorized)
    Set authorized = ($$$ISOK(sc)) && pAuthorized
    Set pAuthorized = authorized
    If 'authorized {
        Do ..RecordAccessDecision("entitlement-denied", "resource="_..#RESOURCE)
    }
    Quit $$$OK
}

/// Confirms the caller's identity on every REST and WebSocket request. The
/// MCP Server CSP application is provisioned with Password authentication, so
/// IRIS itself rejects a missing or wrong credential before the request ever
/// reaches this class (and writes the platform %LOGIN/LoginFailure record).
/// This hook therefore verifies that the forwarded Basic credential is
/// present and well formed, and that the identity IRIS established for the
/// request is the one the credential names. It only falls back to
/// $SYSTEM.Security.Login when the caller identity was not established by the
/// CSP dispatcher, which keeps the credential check on the same path for
/// non-CSP invocations. Demo mode is explicitly unauthenticated and skips the
/// check entirely.
ClassMethod OnAuthenticate(authType As %String, auth As %String, headers As %DynamicObject = "") As %Status
{
    If ##class(br.musketeers.InteropMCP.Setup).GetMode() = "demo" Quit $$$OK
    Set scheme = $ZConvert(authType, "L")
    If scheme = "" {
        Do ..RecordAccessDecision("authentication-denied", "missing-credential")
        Quit $$$ERROR($$$AccessDenied)
    }
    If scheme '= "basic" {
        Do ..RecordAccessDecision("authentication-denied", "unsupported-scheme")
        Quit $$$ERROR($$$AccessDenied)
    }
    Set decoded = ""
    Try {
        Set decoded = $System.Encryption.Base64Decode(auth)
    } Catch ex {
        Set decoded = ""
    }
    Set username = $Piece(decoded, ":", 1)
    If (decoded = "") || (username = "") {
        Do ..RecordAccessDecision("authentication-denied", "malformed-credential", username)
        Quit $$$ERROR($$$AccessDenied)
    }
    Set password = $Piece(decoded, ":", 2, *)
    If ($USERNAME '= "") && ($USERNAME '= "UnknownUser") && ($USERNAME = username) Quit $$$OK
    If '$System.Security.Login(username, password) Quit $$$ERROR($$$AccessDenied)
    Quit $$$OK
}

/// Handles authentication failure. Missing or malformed Basic credentials get
/// a gateway audit record before the base class returns its JSON 401. A
/// well-formed but wrong password is left to IRIS's own %LOGIN/LoginFailure
/// audit so the gateway does not duplicate or mislabel it.
ClassMethod Login(skipheader As %Boolean = 1) As %Status
{
    Set header = $Get(%request.CgiEnvs("HTTP_AUTHORIZATION"))
    Set reason = ""
    If header = "" {
        Set reason = "missing-credential"
    } Else {
        If $ZConvert($Piece(header, " ", 1), "L") '= "basic" {
            Set reason = "unsupported-scheme"
        } Else {
            Set encoded = $Piece(header, " ", 2)
            If encoded = "" {
                Set reason = "malformed-credential"
            } Else {
                Set decoded = ""
                Try {
                    Set decoded = $System.Encryption.Base64Decode(encoded)
                } Catch ex {
                    Set decoded = ""
                }
                If (decoded = "") || ($Piece(decoded, ":", 1) = "") Set reason = "malformed-credential"
            }
        }
    }
    If reason '= "" Do ..RecordAccessDecision("authentication-denied", reason)
    Quit ##super(skipheader)
}

}
