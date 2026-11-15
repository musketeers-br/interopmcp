"""InteropMCP - extração de texto de um PDF em base64.

O agente lê texto, não binário: quando o chamador anexa um documento ao
endpoint REST, o texto do documento é extraído aqui e entregue ao agente
junto com o objetivo da chamada.

Este módulo é carregado no IRIS pelo Setup da demonstração e chamado do
ObjectScript através do Python embarcado:

    set py = ##class(%SYSTEM.Python).Import("interopmcp_pdf")
    set txt = py.extractText(b64)

O nome da função não leva sublinhado: a ponte do IRIS para o Python resolve o
método até o primeiro sublinhado.

Lança exceção quando o documento não é um PDF legível (erro de parsing).
Devolve string vazia quando o PDF é válido mas não contém texto extraível.
"""

import base64
import io


def extractText(pdf_base64):
    """Extrai o texto de um PDF recebido em base64.

    Argumentos:
        pdf_base64: o documento como string base64.

    Retorna:
        O texto do documento (pode ser string vazia se o PDF for válido mas
        não tiver texto extraível).

    Levanta:
        ValueError: quando o documento não é um PDF válido.
        Exception: outros erros de parsing.
    """
    if not pdf_base64:
        raise ValueError("empty input")

    try:
        raw = base64.b64decode(pdf_base64, validate=False)
    except Exception as e:
        raise ValueError("invalid base64") from e

    if not raw:
        raise ValueError("empty after decode")

    try:
        from pypdf import PdfReader
    except Exception as e:
        raise RuntimeError("pypdf not available") from e

    try:
        reader = PdfReader(io.BytesIO(raw))
        pages = []
        for page in reader.pages:
            pages.append(page.extract_text() or "")
        return "\n".join(pages).strip()
    except Exception as e:
        raise ValueError("invalid PDF") from e
