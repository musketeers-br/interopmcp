"""Python smoke client for the IRIS InteropMCP protocol contract.

Skeleton: connects to the InteropMCP endpoint and exercises tools/list +
tools/call (+ get_invocation_status for async tools).
"""

from __future__ import annotations

import argparse
import json
import sys

try:
    from mcp.client.stdio import stdio_client
    from mcp import ClientSession
except ImportError:  # pragma: no cover - MCP client optional until container build
    stdio_client = None  # type: ignore[assignment]
    ClientSession = None  # type: ignore[assignment]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="IRIS MCP Gateway smoke client")
    parser.add_argument("--endpoint", required=True, help="InteropMCP endpoint URL")
    parser.add_argument("--tool", help="Tool name to invoke")
    parser.add_argument("--params", default="{}", help="JSON tool parameters")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if ClientSession is None:
        print("mcp client library not installed (see python/smoke/requirements.txt)")
        return 1
    print(f"[smoke] endpoint={args.endpoint} tool={args.tool}")
    # TODO: open ClientSession, call tools/list, then tools/call with args.params
    print("[smoke] skeleton complete; wire session once endpoint is provisioned")
    return 0


if __name__ == "__main__":
    sys.exit(main())
