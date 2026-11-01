"""Shared helpers for InteropMCP HTTP integration tests.

Kept in a plain importable module (not conftest.py, which pytest loads
specially and cannot be imported as ``conftest``) so both conftest fixtures
and test modules can reuse them.
"""

from __future__ import annotations

import json

import requests

INITIALIZE_PAYLOAD = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "conformance", "version": "1"},
    },
}


def mcp_initialize(base_url: str, headers: dict[str, str] | None) -> dict[str, str] | None:
    """Perform the MCP initialize handshake and return the headers (including
    mcp-session-id) to forward on subsequent requests, or None when the
    handshake itself is refused (e.g. missing credentials)."""
    request_headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
    }
    if headers:
        request_headers.update(headers)
    response = requests.post(base_url, json=INITIALIZE_PAYLOAD, headers=request_headers, timeout=20)
    if response.status_code >= 400:
        return None
    session_id = response.headers.get("mcp-session-id", "").strip()
    if not session_id:
        return None
    return {"mcp-session-id": session_id}


def mcp_rpc_body(response: requests.Response) -> dict:
    """Parse a JSON-RPC response body, handling text/event-stream (SSE) and
    non-JSON error bodies gracefully (returns {} when unparseable)."""
    content_type = response.headers.get("content-type", "")
    if "text/event-stream" in content_type:
        payload = None
        for line in response.text.splitlines():
            if not line.startswith("data:"):
                continue
            candidate = line[5:].strip()
            if not candidate or candidate == "[DONE]":
                continue
            try:
                payload = json.loads(candidate)
            except json.JSONDecodeError:
                continue
        return payload or {}
    try:
        return response.json()
    except (ValueError, json.JSONDecodeError):
        return {}
