"""Shared fixtures for InteropMCP HTTP integration tests."""

from __future__ import annotations

import os
import sys

# Make the sibling helper module importable regardless of pytest's import mode.
sys.path.insert(0, os.path.dirname(__file__))

import base64

from typing import Any, Callable

import pytest
import requests


@pytest.fixture(scope="session")
def base_url() -> str:
    return os.environ.get(
        "INTEROPMCP_BASE_URL", "http://localhost:8080/mcp/interopmcp"
    )


@pytest.fixture(scope="session")
def iris_url() -> str:
    return os.environ.get("INTEROPMCP_IRIS_URL", "http://localhost:52773")


@pytest.fixture(scope="session")
def basic_header() -> dict[str, str]:
    value = os.environ.get("INTEROPMCP_BASIC")
    if value:
        if not value.lower().startswith("basic "):
            value = "Basic " + value
        return {"Authorization": value}

    username = os.environ.get("INTEROPMCP_USER", "mcp_demo")
    password = os.environ.get("INTEROPMCP_DEMO_PASSWORD")
    if not password:
        pytest.skip("INTEROPMCP_BASIC or INTEROPMCP_DEMO_PASSWORD is required")
    token = base64.b64encode(f"{username}:{password}".encode()).decode()
    return {"Authorization": f"Basic {token}"}


@pytest.fixture(scope="session")
def iris_query(iris_url: str) -> Callable[[str, list[str] | None], dict[str, Any]]:
    """Run a read-only SQL query in %SYS through the Atelier REST API."""

    username = os.environ.get("INTEROPMCP_IRIS_USER", "_SYSTEM")
    password = os.environ.get("INTEROPMCP_IRIS_PASSWORD", "SYS")

    def _query(sql: str, parameters: list[str] | None = None) -> dict[str, Any]:
        response = requests.post(
            f"{iris_url}/api/atelier/v1/%SYS/action/query",
            auth=(username, password),
            json={"query": sql, "parameters": parameters or []},
            timeout=15,
        )
        if response.status_code == 404:
            pytest.skip("Atelier query endpoint is unavailable")
        response.raise_for_status()
        return response.json()

    return _query


@pytest.fixture(scope="session")
def mcp_call(base_url: str) -> Callable[[dict[str, str] | None, dict], requests.Response]:
    """Send one JSON-RPC request to the gateway and return the raw response.

    Handles both plain JSON and text/event-stream (SSE) responses. The caller
    is responsible for asserting on the status code and parsing the body.
    """

    def _call(headers: dict[str, str] | None, payload: dict) -> requests.Response:
        request_headers = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
        }
        if headers:
            request_headers.update(headers)
        return requests.post(base_url, json=payload, headers=request_headers, timeout=20)

    return _call
