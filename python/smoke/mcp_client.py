"""Python smoke client for the IRIS InteropMCP HTTP endpoint.

Calls tools/list, optionally tools/call, with an optional Basic Authorization
header. The client never prints the credential value.
"""

from __future__ import annotations

import argparse
import base64
import json
import sys

import httpx

TOOLS_LIST = "tools/list"
TOOLS_CALL = "tools/call"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="IRIS MCP Gateway smoke client")
    parser.add_argument("--endpoint", required=True, help="InteropMCP endpoint URL")
    parser.add_argument("--tool", help="Tool name to invoke")
    parser.add_argument("--params", default="{}", help="JSON tool parameters")
    parser.add_argument(
        "--basic",
        help="Base64(username:password), username:password, or a full Basic header value",
    )
    parser.add_argument("--timeout", type=float, default=30.0, help="Request timeout in seconds")
    return parser.parse_args()


def basic_header(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    if value.lower().startswith("basic "):
        return value
    if ":" in value:
        value = base64.b64encode(value.encode()).decode()
    return f"Basic {value}"


def parse_response(response: httpx.Response) -> dict:
    content_type = response.headers.get("content-type", "")
    if "text/event-stream" in content_type:
        payload = None
        for line in response.text.splitlines():
            if not line.startswith("data:"):
                continue
            candidate = line[5:].strip()
            if not candidate or candidate == "[DONE]":
                continue
            payload = json.loads(candidate)
        if payload is None:
            raise ValueError("event-stream response contained no JSON data")
        return payload
    return response.json()


def rpc(endpoint: str, payload: dict, headers: dict[str, str], timeout: float) -> dict:
    response = httpx.post(endpoint, json=payload, headers=headers, timeout=timeout)
    try:
        body = parse_response(response)
    except (ValueError, json.JSONDecodeError):
        body = {"http_status": response.status_code, "text": response.text}
    if response.status_code >= 400:
        print(json.dumps(body, indent=2))
        raise SystemExit(1)
    if "error" in body:
        print(json.dumps(body, indent=2))
        raise SystemExit(1)
    return body


def main() -> int:
    args = parse_args()
    headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
    }
    authorization = basic_header(args.basic or "")
    if authorization:
        headers["Authorization"] = authorization

    tools = rpc(
        args.endpoint,
        {"jsonrpc": "2.0", "id": 1, "method": TOOLS_LIST},
        headers,
        args.timeout,
    )
    print(json.dumps(tools, indent=2))
    if not args.tool:
        return 0

    try:
        params = json.loads(args.params)
    except json.JSONDecodeError as exc:
        print(f"invalid --params JSON: {exc}", file=sys.stderr)
        return 2

    result = rpc(
        args.endpoint,
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": TOOLS_CALL,
            "params": {"name": args.tool, "arguments": params},
        },
        headers,
        args.timeout,
    )
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
