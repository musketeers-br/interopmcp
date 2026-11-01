"""US3: the caller's identity is attributed to every tool invocation.

The gateway attributes a call to the authenticated IRIS user ($USERNAME in
secured mode) and records it as Invocations.AgentIdentity. That attribution
is asserted directly at the IRIS unit-test level
(tests/.../TestCurrentAgent.cls, TestInvocationRecordsCallerIdentity). This
file covers the HTTP-level contract: an authenticated caller whose identity
is established can execute a tool.
"""

from __future__ import annotations

from mcp_helpers import mcp_initialize, mcp_rpc_body

PAYLOOKUP = {
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {"name": "mcp_interopmcp_PayLookup", "arguments": {"OrderId": "IDENTITY1"}},
}


def test_authenticated_caller_can_execute(base_url: str, mcp_call, basic_header: dict) -> None:
    session_headers = mcp_initialize(base_url, basic_header)
    assert session_headers is not None, "authenticated caller could not complete the handshake"
    response = mcp_call({**basic_header, **session_headers}, PAYLOOKUP)
    body = mcp_rpc_body(response)
    assert response.status_code < 400, f"authenticated caller unexpectedly refused: {body}"
    assert "error" not in body and body.get("isError") is not True, f"authenticated caller errored: {body}"
    content = body.get("result", {}).get("content", [])
    assert any(
        isinstance(entry, dict) and entry.get("type") == "text" and entry.get("text")
        for entry in content
    ), f"authenticated caller got no tool result: {body}"
