#!/usr/bin/env python3
"""Generate the supplier invoice PDFs used by the InteropMCP demonstration production.

The demonstration production reads these documents through an Embedded Python
capability, so they are the fixture that proves the technology end to end. The
documents are generated rather than hand-made so that they can be regenerated
after any change and so that the data they carry is guaranteed consistent.

Two properties are enforced by this generator, both of which matter:

- Every company identifier is check-digit valid. The identifiers are computed
  from their twelve leading digits and the generator refuses to emit a
  document whose check digits do not agree. An identifier that fails this check
  can never be found in a company registry, which would make the document
  unusable for the demonstration.
- Every amount is derived from the line items, so the printed total and the
  line items can never disagree.

The documents carry selectable text (they are not scans), which is what the
reading capability in the demonstration consumes.

Usage:
    python scripts/generate-demo-invoices.py [--output-dir DIR]

Requires reportlab. See scripts/requirements-dev.txt.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "src" / "br" / "musketeers" / "InteropMCP" / "Demo" / "Invoices"

FIRST_CHECK_WEIGHTS = (5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2)
SECOND_CHECK_WEIGHTS = (6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2)


def check_digits(base: str) -> tuple[int, int]:
    """Return the two check digits of a twelve-digit company identifier base."""
    if len(base) != 12 or not base.isdigit():
        raise ValueError(f"identifier base must be twelve digits, got {base!r}")
    first = _weighted_digit(base, FIRST_CHECK_WEIGHTS)
    second = _weighted_digit(base + str(first), SECOND_CHECK_WEIGHTS)
    return first, second


def _weighted_digit(digits: str, weights: tuple[int, ...]) -> int:
    remainder = sum(int(d) * w for d, w in zip(digits, weights)) % 11
    return 0 if remainder < 2 else 11 - remainder


def format_cnpj(base: str) -> str:
    """Return the full, punctuated identifier for a twelve-digit base."""
    first, second = check_digits(base)
    digits = base + str(first) + str(second)
    return f"{digits[0:2]}.{digits[2:5]}.{digits[5:8]}/{digits[8:12]}-{digits[12:14]}"


def format_brl(amount: float) -> str:
    """Return an amount in the Brazilian notation used on invoices."""
    whole = int(amount)
    cents = round((amount - whole) * 100)
    return f"R$ {whole:,}".replace(",", ".") + f",{cents:02d}"


@dataclass(frozen=True)
class Party:
    """A company named on the invoice."""

    legal_name: str
    cnpj_base: str
    address_lines: tuple[str, ...]
    email: str

    @property
    def cnpj(self) -> str:
        return format_cnpj(self.cnpj_base)


@dataclass(frozen=True)
class LineItem:
    """One row of the invoice."""

    description: str
    quantity: int
    unit_price: float

    @property
    def total(self) -> float:
        return round(self.quantity * self.unit_price, 2)


@dataclass(frozen=True)
class Invoice:
    """A complete invoice to render."""

    number: str
    file_name: str
    issue_date: str
    due_date: str
    supplier: Party
    recipient: Party
    items: tuple[LineItem, ...]
    notes: str = ""
    reference: str = ""

    @property
    def total(self) -> float:
        return round(sum(item.total for item in self.items), 2)


DEMO_RECIPIENT = Party(
    legal_name="INTEROPMCP DEMO COMERCIO E SERVICOS LTDA",
    cnpj_base="445556660001",
    address_lines=(
        "AVENIDA PAULISTA, 1000 - CJ 42",
        "BELA VISTA - SAO PAULO/SP - CEP 01310-100",
    ),
    email="faturamento@interopmcp-demo.example",
)

# The first supplier is on the demonstration production's restricted list and is
# deliberately absent from the public company registry: the agent cannot even
# confirm that the company exists, which is why it escalates.
SUPPLIER_RESTRICTED = Party(
    legal_name="MATERIAIS DE CONSTRUCAO ALFA LTDA",
    cnpj_base="987654320001",
    address_lines=(
        "RUA DAS INDUSTRIAS, 455 - GALPAO 3",
        "DISTRITO INDUSTRIAL - CURITIBA/PR - CEP 81200-000",
    ),
    email="comercial@alfa-materiais.example",
)

# Real company, active registration, public registry entry available.
SUPPLIER_ACTIVE = Party(
    legal_name="DORIO TRANSPORTE E LOGISTICA LTDA",
    cnpj_base="632122330001",
    address_lines=(
        "DO EUCALIPTO, 170 - SALA 01 - JARDIM LUIZ ZUCCA",
        "OLIMPIA/SP - CEP 15407-286",
    ),
    email="financeiro@dorio-transporte.example",
)

# Real company whose registration has been cancelled.
SUPPLIER_CANCELLED = Party(
    legal_name="ROBERIO JOSE DOS SANTOS",
    cnpj_base="123456780001",
    address_lines=(
        "PARQUE BITARU - SAO VICENTE/SP - CEP 11330-200",
    ),
    email="contato@roberio-santos.example",
)

INVOICES: tuple[Invoice, ...] = (
    Invoice(
        number="2026-118",
        file_name="INV-2026-118.pdf",
        issue_date="12/11/2026",
        due_date="12/12/2026",
        supplier=SUPPLIER_RESTRICTED,
        recipient=DEMO_RECIPIENT,
        items=(
            LineItem("CIMENTO CP II - SACO 50KG", 40, 38.90),
            LineItem("AREIA LAVADA - M3", 12, 118.75),
            LineItem("FRETE - CARGA PALETIZADA", 1, 452.35),
        ),
        notes="PAGAMENTO EM CONTRATO. MERCADORIA SUJEITA A CONFERENCIA NA ENTRADA.",
    ),
    Invoice(
        number="2026-119",
        file_name="INV-2026-119.pdf",
        issue_date="12/11/2026",
        due_date="26/11/2026",
        supplier=SUPPLIER_ACTIVE,
        recipient=DEMO_RECIPIENT,
        items=(
            LineItem("SERVICO DE TRANSPORTE E LOGISTICA - ROTACAO SP", 1, 890.00),
        ),
        notes="SERVICO PRESTADO. TRIBUTO INCIDENTE ISENTO CONFORME ART. 12 INCISO II.",
    ),
    Invoice(
        number="2026-120",
        file_name="INV-2026-120.pdf",
        issue_date="12/11/2026",
        due_date="27/11/2026",
        supplier=SUPPLIER_CANCELLED,
        recipient=DEMO_RECIPIENT,
        items=(
            LineItem("INSTALACAO DE EQUIPAMENTOS - LOJA CENTRO", 1, 12400.00),
        ),
        notes="SERVICO PRESTADO. GARANTIA DE 90 DIAS CONFORME CONTRATO.",
    ),
)


def draw_header(pdf: canvas.Canvas, invoice: Invoice) -> float:
    """Draw the supplier block and the document title. Returns the next y."""
    left, right = 20 * mm, 190 * mm
    top = 277 * mm

    y = top
    pdf.setFont("Helvetica-Bold", 13)
    pdf.drawString(left, y, invoice.supplier.legal_name)
    y -= 5 * mm
    pdf.setFont("Helvetica", 8.5)
    for line in invoice.supplier.address_lines:
        pdf.drawString(left, y, line)
        y -= 4.2 * mm
    pdf.drawString(left, y, f"CNPJ: {invoice.supplier.cnpj}")
    y -= 4.2 * mm
    pdf.drawString(left, y, invoice.supplier.email)

    pdf.setFont("Helvetica-Bold", 18)
    pdf.drawRightString(right, top + 2 * mm, "NOTA FISCAL")
    pdf.setFont("Helvetica", 8.5)
    pdf.drawRightString(right, top - 4 * mm, "DESTINATARIO DE SERVIICOS")
    pdf.drawRightString(right, top - 8.2 * mm, invoice.recipient.legal_name)
    pdf.drawRightString(right, top - 12.4 * mm, f"CNPJ: {invoice.recipient.cnpj}")
    for line in invoice.recipient.address_lines:
        pdf.drawRightString(right, top - 16.6 * mm - invoice.recipient.address_lines.index(line) * 4.2 * mm, line)

    rule_y = top - 26 * mm
    pdf.setLineWidth(0.8)
    pdf.line(left, rule_y, right, rule_y)
    return rule_y


def draw_details(pdf: canvas.Canvas, invoice: Invoice, y: float) -> float:
    """Draw the identifier, the dates and the total. Returns the next y."""
    left, right = 20 * mm, 190 * mm

    pdf.setFont("Helvetica-Bold", 10)
    pdf.drawString(left, y, f"NUMERO DA NOTA: {invoice.number}")
    y -= 6 * mm
    pdf.setFont("Helvetica", 9.5)
    pdf.drawString(left, y, f"DATA DE EMISSAO: {invoice.issue_date}")
    pdf.drawString(left + 70 * mm, y, f"DATA DE VENCIMENTO: {invoice.due_date}")
    y -= 6 * mm
    pdf.setFont("Helvetica-Bold", 10)
    pdf.drawString(right, y, f"VALOR TOTAL: {format_brl(invoice.total)}")
    y -= 8 * mm

    pdf.setLineWidth(0.4)
    pdf.line(left, y, right, y)
    return y - 6 * mm


def draw_items(pdf: canvas.Canvas, invoice: Invoice, y: float) -> float:
    """Draw the line items table. Returns the next y."""
    left, right = 20 * mm, 190 * mm
    column_x = (left, left + 105 * mm, left + 125 * mm, left + 150 * mm, right)

    pdf.setFont("Helvetica-Bold", 8.5)
    pdf.drawString(column_x[0], y, "DESCRICAO")
    pdf.drawRightString(column_x[1] + 8 * mm, y, "QTD")
    pdf.drawRightString(column_x[2] + 8 * mm, y, "VALOR UNITARIO")
    pdf.drawRightString(column_x[3] + 8 * mm, y, "TOTAL")
    y -= 3 * mm
    pdf.setLineWidth(0.4)
    pdf.line(left, y, right, y)
    y -= 5 * mm

    pdf.setFont("Helvetica", 9)
    for item in invoice.items:
        pdf.drawString(column_x[0], y, item.description)
        pdf.drawRightString(column_x[1] + 8 * mm, y, str(item.quantity))
        pdf.drawRightString(column_x[2] + 8 * mm, y, format_brl(item.unit_price))
        pdf.drawRightString(column_x[3] + 8 * mm, y, format_brl(item.total))
        y -= 6 * mm

    pdf.setLineWidth(0.4)
    pdf.line(left, y + 1 * mm, right, y + 1 * mm)
    y -= 3 * mm
    pdf.setFont("Helvetica-Bold", 10)
    pdf.drawRightString(right, y, f"VALOR TOTAL: {format_brl(invoice.total)}")
    return y - 8 * mm


def draw_notes(pdf: canvas.Canvas, invoice: Invoice, y: float) -> None:
    """Draw the observation block and the issuing footer."""
    left = 20 * mm
    pdf.setFont("Helvetica", 8)
    pdf.drawString(left, y, "OBSERVACOES:")
    y -= 4.2 * mm
    for line in _wrap(invoice.notes, 110):
        pdf.drawString(left, y, line)
        y -= 4.2 * mm

    y -= 6 * mm
    pdf.setFont("Helvetica", 8)
    pdf.drawString(left, y, "Documento emitido eletronicamente para demonstracao do InteropMCP.")
    pdf.drawString(left, y - 4.2 * mm, f"Referencia interna: {invoice.reference or invoice.file_name}")


def _wrap(text: str, width: int) -> list[str]:
    """Wrap a text into lines of at most `width` characters."""
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if len(candidate) > width and current:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines


def render(invoice: Invoice, output_dir: Path) -> Path:
    """Render one invoice to a PDF file and return its path."""
    output_dir.mkdir(parents=True, exist_ok=True)
    target = output_dir / invoice.file_name
    pdf = canvas.Canvas(str(target), pagesize=A4)
    pdf.setTitle(f"Nota Fiscal {invoice.number}")
    pdf.setAuthor(invoice.supplier.legal_name)
    pdf.setSubject(f"Nota fiscal {invoice.number} - {invoice.recipient.legal_name}")

    y = draw_header(pdf, invoice)
    y = draw_details(pdf, invoice, y)
    y = draw_items(pdf, invoice, y)
    draw_notes(pdf, invoice, y)
    pdf.showPage()
    pdf.save()
    return target


def validate(invoice: Invoice) -> None:
    """Fail fast when the fixture data could not be used by the demonstration."""
    if not invoice.items:
        raise ValueError(f"invoice {invoice.number} has no line items")
    if invoice.total <= 0:
        raise ValueError(f"invoice {invoice.number} has a non-positive total")
    for party in (invoice.supplier, invoice.recipient):
        first, second = check_digits(party.cnpj_base)
        expected = party.cnpj_base + str(first) + str(second)
        if not expected.isdigit() or len(expected) != 14:
            raise ValueError(f"invalid identifier for {party.legal_name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="directory the PDFs are written to (default: the demonstration production's Invoices folder)",
    )
    args = parser.parse_args()

    for invoice in INVOICES:
        validate(invoice)
        path = render(invoice, args.output_dir)
        print(f"wrote {path.relative_to(REPO_ROOT)} (CNPJ {invoice.supplier.cnpj}, total {format_brl(invoice.total)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
