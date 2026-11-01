"""US1: missing/invalid credentials are refused before tool execution.

Verified bridge behavior (against the running gateway):

- A request without an Authorization header is refused with HTTP 401 at the
  gateway level, before any tool execution (initialize and tools/call).
- A well-formed but wrong password is forwarded to the IRIS MCP service. The
  handshake (initialize) still answers 200 because the bridge answers it from
  its own service info, but tool execution then fails: service discovery
  against IRIS is refused (IRIS answers 401 to the discovery request) and
  surfaces as a JSON-RPC tool error over HTTP 200. There is no clean HTTP 401
  for a wrong password today (bridge limitation; see the gateway limitation
  notes in specs/002-mcp-gateway-auth).
"""

from __future__ import annotations

import base64

import requests

from mcp_helpers import INITIALIZE_PAYLOAD, mcp_initialize, mcp_rpc_body


def test_missing_credential_returns_401(base_url: str) -> None:
    request_headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
    }
    response = requests.post(base_url, json=INITIALIZE_PAYLOAD, headers=request_headers, timeout=20)
    assert response.status_code == 401, response.text


def test_wrong_password_refuses_tool_execution(base_url: str, mcp_call) -> None:
    wrong_token = base64.b64encode(b"zz_test_auth:definitely-wrong").decode()
    wrong_header = {"Authorization": f"Basic {wrong_token}"}

    session_headers = mcp_initialize(base_url, wrong_header)
    # The handshake answers 200: the bridge does not validate the password
    # there (it answers from its own service info).
    assert session_headers is not None

    payload = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {"name": "mcp_interopmcp_PayLookup", "arguments": {"OrderId": "1"}},
    }
    # Tool execution is refused: discovery against IRIS fails with 401 and
    # surfaces as a JSON-RPC tool error.
    response = mcp_call({**wrong_header, **session_headers}, payload)
    body = mcp_rpc_body(response)
    result = body.get("result", {})
    assert response.status_code >= 400 or "error" in body or result.get("isError") is True, (
        f"expected tool execution to be refused, got {response.status_code}: {body}"
    )
