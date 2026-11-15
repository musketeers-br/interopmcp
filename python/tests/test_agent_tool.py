"""The agent is published on the MCP endpoint, beside the capabilities.

The agent is the production's own entry point: the gateway reaches it exactly
as it reaches every other business service, so it is published as one more
tool. This test asserts that the agent appears, that its published shape is the
one the contract describes - a single goal argument and the adapter's purpose
as its description - and that a run which cannot complete is reported as a
failure rather than as a success.

The test is skipped when no caller credential is configured, because the
endpoint is authenticated.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import pytest
import requests

from mcp_helpers import mcp_initialize, mcp_rpc_body

AGENT_TOOL = "mcp_interopmcp_AgentHost"
BRIDGE_PREFIX = "[Remote Service: local_mcp_interopmcp]"

# How long the test waits for a run's outcome. The contract allows a run two
# minutes past its own bound before the outcome must be recorded, and the
# adapter's default bound is 120 seconds, so the window covers the bound and
# its grace period.
AGENT_OUTCOME_WINDOW_SECONDS = 300


def _published_tools(base_url: str, headers: dict[str, str]) -> dict[str, dict]:
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
        json={"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        headers=request_headers,
        timeout=20,
    )
    body = mcp_rpc_body(response)
    tools = body.get("result", {}).get("tools")
    if tools is None:
        pytest.fail(f"tools/list returned no tool array: {body}")

    published: dict[str, dict] = {}
    for tool in tools:
        description = (tool.get("description") or "").replace(BRIDGE_PREFIX, "").strip()
        published[tool["name"]] = {
            "description": description,
            "inputSchema": tool.get("inputSchema"),
        }
    return published


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
    try:
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
    except requests.RequestException as exc:
        # The bridge re-discovers the endpoint periodically; a call that
        # lands on that moment carries nothing. The caller retries.
        return {"_transport_error": str(exc)}
    body = mcp_rpc_body(response)
    if "error" in body:
        pytest.fail(f"calling {name} failed at the protocol level: {body}")
    return body.get("result", {}).get("structuredContent", {})


def test_the_agent_is_published(base_url: str, basic_header: dict[str, str]) -> None:
    """The agent is one more published tool, with the shape the contract says."""
    published = _published_tools(base_url, basic_header)
    assert AGENT_TOOL in published, (
        f"the agent is not published; the endpoint advertises {sorted(published)}"
    )

    agent = published[AGENT_TOOL]
    schema = agent["inputSchema"]
    assert schema.get("type") == "object"
    assert list(schema.get("properties", {})) == ["Goal"], (
        "the agent takes one argument: the caller's goal"
    )
    assert schema.get("required") == ["Goal"], "the goal is required"
    assert agent["description"], "the agent is published with a description, so a caller can discover it"


def test_the_agent_runs_or_fails_loudly(base_url: str, basic_header: dict[str, str]) -> None:
    """A run either produces a result or is reported as a failure - never a false success.

    Whether the run can complete depends on the deployment having a model
    provider configured, which is an environment concern and not the gateway's.
    What the gateway guarantees is that the outcome is never silently
    successful.

    The agent runs asynchronously: the call returns a processing reference
    immediately, so it never holds the caller's connection, and the answer is
    collected from the invocation afterwards.
    """
    result = _call_tool(
        base_url,
        basic_header,
        AGENT_TOOL,
        {"Goal": "assess the risk of company 12.345.678/0001-95"},
    )
    assert result.get("_status") in ("pending", "ok", "error", "held"), (
        f"the agent returned an unexpected status: {result}"
    )

    if result.get("_status") == "pending":
        # The run is dispatched in the background: the call returns a
        # processing reference and the answer is collected from the invocation.
        invocation_id = result.get("invocationId")
        assert invocation_id, "a pending run carries the invocation to poll"
        rows: list = []
        # The run starts in the production's own queue, so it begins when a
        # worker is free; the window is generous on purpose. The contract
        # allows a run two minutes past its own bound before the outcome must
        # be recorded, and the bound is 120 seconds, so the window covers the
        # bound and its grace period. A poll that returns nothing is retried
        # rather than taken as an outcome: the bridge may be re-discovering
        # the endpoint, and a poll that lands on that moment carries no row.
        deadline = time.monotonic() + AGENT_OUTCOME_WINDOW_SECONDS
        while time.monotonic() < deadline:
            time.sleep(3)
            status = _call_tool(
                base_url,
                basic_header,
                "mcp_interopmcp_GetInvocationStatus",
                {"invocationId": invocation_id},
            )
            rows = status.get("rows", [])
            if rows and rows[0].get("Status") in ("completed", "failed"):
                break
        assert rows, "the run's outcome is retrievable from the invocation store"
        assert rows[0].get("Status") == "completed", (
            f"the run did not complete: {rows[0].get('Status')}"
        )
        assert rows[0].get("Result"), "the completed run carries its answer"
        return

    if result.get("_status") == "error":
        # A failure must point at the invocation that carries the reason.
        invocation_id = result.get("invocationId")
        assert invocation_id, "a failed run must carry the invocation that holds the reason"

        status = _call_tool(
            base_url,
            basic_header,
            "mcp_interopmcp_GetInvocationStatus",
            {"invocationId": invocation_id},
        )
        rows = status.get("rows", [])
        assert rows, "the failed run must be retrievable from the invocation store"
        assert rows[0].get("Status") == "failed", (
            f"a failed run must be recorded as failed, not as {rows[0].get('Status')}"
        )
    else:
        # A completed run carries the agent's answer.
        assert result.get("invocationId"), "a completed run carries its invocation identifier"


def test_the_agent_does_not_publish_itself_as_a_capability(
    base_url: str, basic_header: dict[str, str]
) -> None:
    """The agent's own entry is not a capability: there is exactly one agent tool."""
    published = _published_tools(base_url, basic_header)
    agents = [name for name in published if "Agent" in name]
    assert agents == [AGENT_TOOL], f"expected exactly one agent tool, found {agents}"


def test_the_agent_is_not_part_of_its_own_tool_surface() -> None:
    """The agent's tool surface never contains the agent's own entry.

    The agent reaches the production's capabilities through the published
    tools, so that the classification and the approval gate apply to its
    actions. Its own entry must not be among them, or the agent could call
    itself.
    """
    generated = Path("/tmp/InteropMCP.AgentTools.cls")
    if not generated.exists():
        pytest.skip("the agent's tool class has not been generated on this instance")

    source = generated.read_text(encoding="utf-8")
    assert f"ClassMethod {AGENT_TOOL.replace('mcp_interopmcp_', '')}" not in source, (
        "the agent's own entry must not be part of the tool surface it is given"
    )
