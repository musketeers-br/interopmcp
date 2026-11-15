"""The asynchronous contract of the gateway.

A long-running tool is not answered with the business result: it is answered
with a processing reference, and the result is collected from the invocation
the reference points at. The polling belongs to the caller, so this is where
the contract is checked end to end - the unit test on the server side covers
the gateway's half of it.
"""

from __future__ import annotations

import time

import pytest
import requests

from mcp_helpers import mcp_initialize, mcp_rpc_body

BATCH_RUN_TOOL = "mcp_interopmcp_BatchRun"
STATUS_TOOL = "mcp_interopmcp_GetInvocationStatus"

# The demo batch run finishes in well under a second, but the dispatch is
# asynchronous: the window only has to be long enough for the background job
# to record the outcome.
ASYNC_OUTCOME_WINDOW_SECONDS = 60


def _call_tool(base_url: str, headers: dict[str, str], name: str, arguments: dict) -> dict:
    session = mcp_initialize(base_url, headers)
    if session is None:
        pytest.skip("the MCP endpoint refused the handshake (no valid credential?)")

    request_headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
    }
    request_headers.update(headers)
    request_headers.update(session)

    requests.post(
        base_url,
        json={"jsonrpc": "2.0", "method": "notifications/initialized"},
        headers=request_headers,
        timeout=20,
    )
    response = requests.post(
        base_url,
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        },
        headers=request_headers,
        timeout=120,
    )
    body = mcp_rpc_body(response)
    if "error" in body:
        pytest.fail(f"calling {name} failed at the protocol level: {body}")
    return body.get("result", {}).get("structuredContent", {})


def test_a_long_running_tool_answers_with_a_processing_reference(
    base_url: str, basic_header: dict[str, str]
) -> None:
    result = _call_tool(base_url, basic_header, BATCH_RUN_TOOL, {"ReportSet": "daily"})

    assert result.get("_status") == "pending", "the call is handed a processing reference"
    invocation_id = result.get("invocationId")
    assert invocation_id, "the processing reference names the invocation to poll"


def test_the_answer_of_a_long_running_tool_is_collectable_from_the_invocation(
    base_url: str, basic_header: dict[str, str]
) -> None:
    result = _call_tool(base_url, basic_header, BATCH_RUN_TOOL, {"ReportSet": "daily"})
    invocation_id = result.get("invocationId")
    assert invocation_id, "the processing reference names the invocation to poll"

    deadline = time.monotonic() + ASYNC_OUTCOME_WINDOW_SECONDS
    rows: list = []
    while time.monotonic() < deadline:
        status_result = _call_tool(
            base_url, basic_header, STATUS_TOOL, {"invocationId": invocation_id}
        )
        rows = status_result.get("rows", [])
        if rows and rows[0].get("Status") in ("completed", "failed"):
            break
        time.sleep(1)

    assert rows, "the outcome is retrievable from the invocation store"
    assert rows[0].get("Status") == "completed", (
        f"the invocation did not complete: {rows[0].get('Status')}"
    )
    assert rows[0].get("Result"), "the completed invocation carries the business result"
