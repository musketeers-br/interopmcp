"""Validate a running InteropMCP gateway deployment.

Checks the /mcp/interopmcp endpoint over HTTP: the handshake, the secured-mode
credential gate, the published tool catalog, and a sample tool execution.
Intended to run inside the IRIS container (python3 + requests are available)
against the bridge at localhost:8080, or on the host against a published port.

Exits 0 when every check passes, 1 otherwise. Prints a PASS/FAIL report.

Environment:
  INTEROPMCP_BASE_URL   gateway base URL (default http://localhost:8080/mcp/interopmcp)
  INTEROPMCP_MODE       secured (default) or demo
  INTEROPMCP_BASIC      full "Basic <base64>" header value for an entitled caller
  INTEROPMCP_USER / INTEROPMCP_DEMO_PASSWORD
                        used to build INTEROPMCP_BASIC when INTEROPMCP_BASIC is unset
  EXPECTED_TOOLS        comma-separated tool names the catalog must contain
                        (default PayLookup,RiskCheck,CustomerUpdate,BatchRun,GetInvocationStatus)
"""

from __future__ import annotations

import base64
import json
import os
import sys

try:
    import requests
except ImportError as exc:  # pragma: no cover - environments without requests
    raise SystemExit(f"validate-mcp-config: requests is required: {exc}")


BASE_URL = os.environ.get("INTEROPMCP_BASE_URL", "http://localhost:8080/mcp")
MODE = os.environ.get("INTEROPMCP_MODE", "secured").lower()
EXPECTED_TOOLS = [
    name.strip()
    for name in os.environ.get(
        "EXPECTED_TOOLS",
        "mcp_interopmcp_PayLookup,mcp_interopmcp_RiskCheck,mcp_interopmcp_CustomerUpdate,mcp_interopmcp_BatchRun,mcp_interopmcp_GetInvocationStatus",
    ).split(",")
    if name.strip()
]


def basic_header() -> dict[str, str] | None:
    value = os.environ.get("INTEROPMCP_BASIC")
    if value:
        if not value.lower().startswith("basic "):
            value = "Basic " + value
        return {"Authorization": value}
    username = os.environ.get("INTEROPMCP_USER", "mcp_demo")
    password = os.environ.get("INTEROPMCP_DEMO_PASSWORD")
    if not password:
        return None
    token = base64.b64encode(f"{username}:{password}".encode()).decode()
    return {"Authorization": f"Basic {token}"}


INITIALIZE_PAYLOAD = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "validate-mcp-config", "version": "1"},
    },
}

TOOLS_CALL_PAYLOOKUP = {
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {"name": "mcp_interopmcp_PayLookup", "arguments": {"OrderId": "VALIDATE1"}},
}


def rpc_body(response) -> dict:
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


class Report:
    def __init__(self) -> None:
        self.checks = []
        self.failed = 0

    def check(self, name, ok, detail=""):
        self.checks.append((name, ok, detail))
        if not ok:
            self.failed += 1
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {name}" + (f" - {detail}" if detail and not ok else ""))

    def summary(self):
        print(f"\n{len(self.checks) - self.failed}/{len(self.checks)} checks passed")
        return self.failed == 0


def initialize(base_url, headers):
    request_headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
    }
    if headers:
        request_headers.update(headers)
    return requests.post(base_url, json=INITIALIZE_PAYLOAD, headers=request_headers, timeout=20)


def main() -> int:
    report = Report()
    header = basic_header()
    secured = MODE == "secured"

    # 1. Gateway handshake with a valid credential.
    response = initialize(BASE_URL, header)
    body = rpc_body(response)
    handshake_ok = response.status_code < 400 and body.get("result", {}).get("serverInfo")
    report.check("gateway handshake (authenticated)", handshake_ok, f"HTTP {response.status_code}: {body}")
    if not handshake_ok:
        report.summary()
        return 1
    session_id = response.headers.get("mcp-session-id", "").strip()

    # 2. Secured mode: missing credential is refused at the gateway.
    if secured:
        response = initialize(BASE_URL, None)
        report.check(
            "missing credential refused with 401",
            response.status_code == 401,
            f"HTTP {response.status_code}",
        )
    else:
        report.check("demo mode: credential gate skipped (unauthenticated)", True)

    # 3. Catalog: tools/list returns the expected tools.
    headers = {**(header or {}), **({"mcp-session-id": session_id} if session_id else {})}
    response = requests.post(
        BASE_URL,
        json={"jsonrpc": "2.0", "id": 3, "method": "tools/list"},
        headers={
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
            **headers,
        },
        timeout=20,
    )
    body = rpc_body(response)
    tools = body.get("result", {}).get("tools", []) if body.get("result") else []
    names = [t.get("name") for t in tools] if isinstance(tools, list) else []
    missing = [t for t in EXPECTED_TOOLS if t not in names]
    report.check(
        "catalog exposes expected tools",
        not missing and response.status_code < 400,
        f"missing={missing} names={names}" if missing else f"tools={names}",
    )

    # 4. Tool execution succeeds with a valid credential.
    response = requests.post(
        BASE_URL,
        json=TOOLS_CALL_PAYLOOKUP,
        headers={
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
            **headers,
        },
        timeout=20,
    )
    body = rpc_body(response)
    result = body.get("result", {})
    execution_ok = (
        response.status_code < 400
        and "error" not in body
        and result.get("isError") is not True
        and bool(result.get("content"))
    )
    report.check("sample tool execution (PayLookup)", execution_ok, f"HTTP {response.status_code}: {body}")

    ok = report.summary()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
