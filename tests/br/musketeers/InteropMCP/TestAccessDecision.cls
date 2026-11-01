Class br.musketeers.InteropMCP.TestAccessDecision Extends %UnitTest.TestCase
{

/// The gateway reads the caller identity from the Basic Authorization header.
/// A missing, non-Basic or malformed header yields no identity - the request
/// is then refused and audited - and the password never leaves this method.
Method TestUsernameFromHeader() As %Status
{
    Do $$$AssertEquals(##class(br.musketeers.InteropMCP.MCPService).UsernameFromHeader(""), "", "Missing header yields no identity")
    Do $$$AssertEquals(##class(br.musketeers.InteropMCP.MCPService).UsernameFromHeader("Bearer token123"), "", "Non-Basic scheme yields no identity")
    Do $$$AssertEquals(##class(br.musketeers.InteropMCP.MCPService).UsernameFromHeader("Basic"), "", "Header without credentials yields no identity")
    Set encoded = $System.Encryption.Base64Encode("caller-1:secret")
    Do $$$AssertEquals(##class(br.musketeers.InteropMCP.MCPService).UsernameFromHeader("Basic "_encoded), "caller-1", "Basic header yields the username")
    Set encoded = $System.Encryption.Base64Encode("caller-2:pa:ss")
    Do $$$AssertEquals(##class(br.musketeers.InteropMCP.MCPService).UsernameFromHeader("basic "_encoded), "caller-2", "Scheme is matched case-insensitively")
    Set encoded = $System.Encryption.Base64Encode(":only-password")
    Do $$$AssertEquals(##class(br.musketeers.InteropMCP.MCPService).UsernameFromHeader("Basic "_encoded), "", "Credential without username yields no identity")
    Quit $$$OK
}

/// The access decision is written to the platform audit trail. Recording a
/// decision must never fail the request and must never leak the credential.
Method TestRecordAccessDecision() As %Status
{
    Set sc = ##class(br.musketeers.InteropMCP.MCPService).RecordAccessDecision("authentication-denied", "missing-credential", "caller-1")
    Do $$$AssertStatusOK(sc, "Denial recorded")
    Set sc = ##class(br.musketeers.InteropMCP.MCPService).RecordAccessDecision("entitlement-denied", "resource=InteropMCP_Access", "caller-1")
    Do $$$AssertStatusOK(sc, "Entitlement denial recorded")
    Quit $$$OK
}

/// The entitlement resource and role are provisioned once and stay stable
/// across repeated setup runs, so the gateway never opens itself up by
/// accident.
Method TestResourceAndRoleAreStable() As %Status
{
    Set oldNs = $Namespace
    Set $NAMESPACE = "%SYS"
    Set resource = ##class(Security.Resources).Exists("InteropMCP_Access")
    Set role = ##class(Security.Roles).Exists("InteropMCPRoles")
    Set $NAMESPACE = oldNs
    Do $$$AssertTrue(resource, "Gateway resource exists")
    Do $$$AssertTrue(role, "Gateway role exists")
    Quit $$$OK
}

}
