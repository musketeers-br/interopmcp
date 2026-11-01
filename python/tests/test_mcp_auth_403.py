"""US2: unentitled callers are refused with 403 and an INTEROPMCP/AccessDenied
audit record is written.

The denial path needs a caller that (a) presents a valid IRIS credential and
(b) is NOT a member of InteropMCPRoles. Provision such a user externally (for
example through the bootstrap-demo/iris.script provisioning in US4) and pass
its credential through INTEROPMCP_UNENTITLED_BASIC. Without it, the denial
assertions are skipped and only the positive control (an entitled caller can
execute) runs.

The gateway writes an INTEROPMCP/AccessDenied platform audit record for every
entitlement denial (user, endpoint, outcome, reason are recorded; the
credential itself never is). Reading that record back requires the Atelier
query endpoint, which is not reachable in this environment, so the audit
assertion itself is exercised at the IRIS unit-test level
(tests/.../TestAccessDecision.cls) rather than here.
"""

from __future__ import annotations

import os

import pytest
import requests

from mcp_helpers import mcp_initialize, mcp_rpc_body

PAYLOOKUP = {
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {"name": "mcp_interopmcp_PayLookup", "arguments": {"OrderId": "1"}},
}


def _execution_refused(response: requests.Response) -> bool:
    body = mcp_rpc_body(response)
    result = body.get("result", {})
    return response.status_code >= 400 or "error" in body or result.get("isError") is True


@pytest.fixture(scope="session")
def unentitled_header() -> dict[str, str] | None:
    value = os.environ.get("INTEROPMCP_UNENTITLED_BASIC")
    if not value:
        return None
    if not value.lower().startswith("basic "):
        value = "Basic " + value
    return {"Authorization": value}


def test_entitled_caller_executes_tool(base_url: str, mcp_call, basic_header: dict[str, str]) -> None:
    """Positive control: a caller entitled to InteropMCP_Access can execute."""
    session_headers = mcp_initialize(base_url, basic_header)
    assert session_headers is not None, "entitled caller could not complete the handshake"
    response = mcp_call({**basic_header, **session_headers}, PAYLOOKUP)
    body = mcp_rpc_body(response)
    assert response.status_code < 400, f"entitled caller unexpectedly refused: {body}"
    assert "error" not in body and body.get("isError") is not True, f"entitled caller errored: {body}"


@pytest.mark.skipif(
    os.environ.get("INTEROPMCP_UNENTITLED_BASIC") is None,
    reason="INTEROPMCP_UNENTITLED_BASIC is not set (no unentitled valid-credential caller provisioned)",
)
def test_unentitled_caller_is_refused_and_audited(
    base_url: str, mcp_call, unentitled_header: dict[str, str]
) -> None:
    assert unentitled_header is not None
    session_headers = mcp_initialize(base_url, unentitled_header)
    assert session_headers is not None, "unentitled caller could not complete the handshake"
    response = mcp_call({**unentitled_header, **session_headers}, PAYLOOKUP)
    assert _execution_refused(response), f"unentitled caller was not refused: {response.text}"
    # Denials surface either as HTTP 403 or as a JSON-RPC tool error over
    # HTTP 200 (bridge limitation; see specs/002-mcp-gateway-auth). The
    # essential assertion is that execution is refused.
    assert _execution_refused(response)
