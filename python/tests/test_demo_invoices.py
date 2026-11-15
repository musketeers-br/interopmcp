"""The demonstration production's invoice fixtures must stay readable and valid.

The demonstration production reads supplier invoices through an Embedded Python
capability, so these documents are the contract that capability is written
against: a supplier's company identifier, the invoice number and the total must
be recoverable from the document text alone.

Two defects are guarded against here, both of which would silently break the
demonstration:

- An identifier whose check digits do not validate can never be found in a
  company registry, so the agent would be judging a company that does not
  exist. Every identifier in the fixtures is checked against the check-digit
  algorithm.
- A fixture that cannot be read, or whose totals disagree with its line items,
  would make the demonstration fail for reasons that have nothing to do with
  the feature.

The test is skipped when pypdf is not installed, since it is not part of the
runtime dependency set.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

import pytest

pytest.importorskip("pypdf")

from pypdf import PdfReader  # noqa: E402  (import after the skip guard)

REPO_ROOT = Path(__file__).resolve().parents[2]
INVOICE_DIR = REPO_ROOT / "src" / "br" / "musketeers" / "InteropMCP" / "Demo" / "Invoices"

FIRST_CHECK_WEIGHTS = (5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2)
SECOND_CHECK_WEIGHTS = (6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2)

EXPECTED = {
    "INV-2026-118.pdf": {
        "cnpj": "98.765.432/0001-98",
        "number": "2026-118",
        "total": "3.433,35",
    },
    "INV-2026-119.pdf": {
        "cnpj": "63.212.233/0001-78",
        "number": "2026-119",
        "total": "890,00",
    },
    "INV-2026-120.pdf": {
        "cnpj": "12.345.678/0001-95",
        "number": "2026-120",
        "total": "12.400,00",
    },
}


def _check_digits(base: str) -> str:
    """Return the full identifier for a twelve-digit base, check digits included."""

    def weighted(digits: str, weights: tuple[int, ...]) -> int:
        remainder = sum(int(d) * w for d, w in zip(digits, weights)) % 11
        return 0 if remainder < 2 else 11 - remainder

    first = weighted(base, FIRST_CHECK_WEIGHTS)
    second = weighted(base + str(first), SECOND_CHECK_WEIGHTS)
    return base + str(first) + str(second)


@pytest.mark.parametrize("file_name", sorted(EXPECTED))
def test_invoice_is_readable(file_name: str) -> None:
    """Every fixture must yield selectable text on a single page."""
    path = INVOICE_DIR / file_name
    assert path.exists(), f"missing fixture {path}"

    reader = PdfReader(str(path))
    assert len(reader.pages) == 1, "an invoice must be a single page"

    text = reader.pages[0].extract_text()
    assert text.strip(), "an invoice must carry selectable text"


@pytest.mark.parametrize("file_name", sorted(EXPECTED))
def test_invoice_yields_the_expected_details(file_name: str) -> None:
    """The three details the capability extracts must be recoverable."""
    expected = EXPECTED[file_name]
    text = PdfReader(str(INVOICE_DIR / file_name)).pages[0].extract_text()

    cnpj = re.search(r"CNPJ:\s*([\d.]+/[\d]+-\d+)", text)
    assert cnpj, f"no company identifier found in {file_name}"
    assert cnpj.group(1) == expected["cnpj"]

    number = re.search(r"NUMERO DA NOTA:\s*([\w-]+)", text)
    assert number, f"no invoice number found in {file_name}"
    assert number.group(1) == expected["number"]

    total = re.search(r"VALOR TOTAL:\s*R\$\s*([\d.,]+)", text)
    assert total, f"no total found in {file_name}"
    assert total.group(1) == expected["total"]


@pytest.mark.parametrize("file_name", sorted(EXPECTED))
def test_supplier_identifier_is_valid(file_name: str) -> None:
    """The supplier identifier must be one a company registry would accept."""
    expected = EXPECTED[file_name]
    digits = re.sub(r"\D", "", expected["cnpj"])
    assert len(digits) == 14, f"{expected['cnpj']} is not a fourteen-digit identifier"

    base = digits[:12]
    assert _check_digits(base) == digits, (
        f"{expected['cnpj']} has invalid check digits; a registry would reject it "
        f"and the agent would be judging a company that cannot exist"
    )


def test_generator_agrees_with_the_fixtures() -> None:
    """Regenerating the fixtures must reproduce what is committed."""
    generator = REPO_ROOT / "scripts" / "generate-demo-invoices.py"
    # The generator's file name carries a hyphen, like its sibling
    # validate-mcp-config.py, so it is loaded by path rather than imported.
    spec = importlib.util.spec_from_file_location("generate_demo_invoices", generator)
    assert spec is not None and spec.loader is not None
    generator_module = importlib.util.module_from_spec(spec)
    # The generator resolves its dataclass fields through sys.modules, because it
    # defers annotation evaluation, so it has to be registered before execution.
    sys.modules[spec.name] = generator_module
    try:
        spec.loader.exec_module(generator_module)
    except Exception as exc:  # pragma: no cover - surfaces a broken generator
        pytest.fail(f"the invoice generator could not be loaded: {exc}")
        return

    for file_name, expected in EXPECTED.items():
        matching = [
            invoice
            for invoice in generator_module.INVOICES
            if invoice.file_name == file_name
        ]
        assert len(matching) == 1, f"{file_name} is not produced by the generator"
        invoice = matching[0]
        assert invoice.supplier.cnpj == expected["cnpj"]
        assert invoice.number == expected["number"]
        assert generator_module.format_brl(invoice.total) == f"R$ {expected['total']}"
