"""US4: run the gateway configuration validator as a subprocess.

The validator (scripts/validate-mcp-config.py) checks the running gateway:
handshake, secured-mode credential gate, published catalog, and sample tool
execution. This test invokes it and asserts it exits 0.

It is skipped when no valid caller credential is configured
(INTEROPMCP_BASIC, or INTEROPMCP_USER + INTEROPMCP_DEMO_PASSWORD), since the
validator cannot authenticate against a secured endpoint without one.
"""

from __future__ import annotations

import os
import subprocess
import sys

import pytest


def _has_credential() -> bool:
    if os.environ.get("INTEROPMCP_BASIC"):
        return True
    return bool(os.environ.get("INTEROPMCP_USER") and os.environ.get("INTEROPMCP_DEMO_PASSWORD"))


@pytest.mark.skipif(
    not _has_credential(),
    reason="INTEROPMCP_BASIC (or INTEROPMCP_USER + INTEROPMCP_DEMO_PASSWORD) is not set",
)
def test_config_validator_exits_zero() -> None:
    validator = os.path.join(
        os.path.dirname(__file__), "..", "..", "scripts", "validate-mcp-config.py"
    )
    result = subprocess.run(
        [sys.executable, validator],
        capture_output=True,
        text=True,
        timeout=120,
    )
    print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    assert result.returncode == 0, "configuration validator failed"
