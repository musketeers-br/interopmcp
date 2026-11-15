"""The published MCP tool surface must survive the AI agent adapter.

The gateway's catalogue build is shared by every published tool, so a change
to it that recognises an agent can break the discovery of the business
capabilities that were already published. When that happens the endpoint stops
advertising the tools it used to advertise, and every caller that depends on
them breaks at once.

This module turns that risk into an executable contract. The baseline in
``baselines/mcp-tools.json`` was captured from the running gateway before the
agent adapter existed. The rules it enforces:

- every baseline tool is still published;
- every baseline tool's input schema is exactly what it was;
- a description is never removed — it may only be added or enriched.

A tool the baseline does not know about is allowed: that is the agent being
published alongside the capabilities.

The test is skipped when no caller credential is configured, because the
endpoint is authenticated.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from mcp_helpers import mcp_initialize, mcp_rpc_body

BASELINE_PATH = Path(__file__).parent / "baselines" / "mcp-tools.json"

# The MCP bridge decorates every description with the remote service it
# belongs to. That decoration is the bridge's, not the gateway's, so it is
# stripped before the comparison.
BRIDGE_PREFIX = re.compile(r"^\[Remote Service: [^\]]*\]\s*")


def _load_baseline() -> dict:
    return json.loads(BASELINE_PATH.read_text(encoding="utf-8"))


def _published_tools(base_url: str, headers: dict[str, str]) -> dict[str, dict]:
    """Return the published tools as {name: {description, inputSchema}}."""
    session = mcp_initialize(base_url, headers)
    if session is None:
        pytest.skip("the MCP endpoint refused the handshake (no valid credential?)")

    request_headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
    }
    request_headers.update(headers)
    request_headers.update(session)

    import requests

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
        description = BRIDGE_PREFIX.sub("", tool.get("description") or "").strip()
        published[tool["name"]] = {
            "description": description,
            "inputSchema": tool.get("inputSchema"),
        }
    return published


def test_published_tool_surface_is_preserved(base_url: str, basic_header: dict[str, str]) -> None:
    """No tool that was published before may disappear or change its schema."""
    baseline = _load_baseline()
    published = _published_tools(base_url, basic_header)

    missing = [tool["name"] for tool in baseline["tools"] if tool["name"] not in published]
    assert not missing, (
        "these tools were published before the agent adapter and are no longer "
        f"published: {missing}. The catalogue build or the tool set stopped "
        "advertising them, which breaks every caller that used them."
    )

    for tool in baseline["tools"]:
        current = published[tool["name"]]
        assert current["inputSchema"] == tool["inputSchema"], (
            f"the input schema of {tool['name']} changed. Callers send the "
            "published argument names, so a change here is a breaking change."
        )
        assert current["description"].startswith(tool["description"]), (
            f"the description of {tool['name']} was removed or rewritten. "
            "Descriptions may only be added or enriched."
        )


def test_published_tool_count_does_not_shrink(base_url: str, basic_header: dict[str, str]) -> None:
    """The endpoint must never advertise fewer tools than it used to."""
    baseline = _load_baseline()
    published = _published_tools(base_url, basic_header)
    assert len(published) >= len(baseline["tools"]), (
        f"the endpoint publishes {len(published)} tools but published "
        f"{len(baseline['tools'])} before the agent adapter was added"
    )


def test_a_capability_still_executes(base_url: str, basic_header: dict[str, str]) -> None:
    """A capability that was published before must still work end to end.

    Publication is only half of the contract: the tool must also still fire
    its business service and return a result.
    """
    import requests

    session = mcp_initialize(base_url, basic_header)
    if session is None:
        pytest.skip("the MCP endpoint refused the handshake (no valid credential?)")

    request_headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
    }
    request_headers.update(basic_header)
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
            "params": {
                "name": "mcp_interopmcp_PayLookup",
                "arguments": {"OrderId": "88201", "CustomerId": "C-1"},
            },
        },
        headers=request_headers,
        timeout=60,
    )
    body = mcp_rpc_body(response)
    assert "error" not in body, f"calling a published capability failed: {body}"
    assert body.get("result"), f"calling a published capability returned nothing: {body}"
