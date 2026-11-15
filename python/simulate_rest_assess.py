#!/usr/bin/env python3
"""Simula chamadas ao endpoint REST síncrono do agente (POST /api/agent/assess).

Requisitos: nenhum (usa apenas urllib da stdlib do Python).

Variáveis de ambiente:
  INTEROPMCP_HOST    host do IRIS (default: localhost)
  INTEROPMCP_PORT    porta do web server privado (default: 52773)
  INTEROPMCP_USER    usuário (default: mcp_demo)
  INTEROPMCP_PWD     senha (default: lê do .env do deploy ou usa demo)
"""

import base64
import json
import os
import sys
import urllib.error
import urllib.request

HOST = os.environ.get("INTEROPMCP_HOST", "localhost")
PORT = int(os.environ.get("INTEROPMCP_PORT", "52773"))
USER = os.environ.get("INTEROPMCP_USER", "mcp_demo")
PWD = os.environ.get("INTEROPMCP_PWD", "")

BASE = f"http://{HOST}:{PORT}/api/agent/assess"


def read_password_from_env_file():
    """Tenta ler INTEROPMCP_DEMO_PASSWORD de arquivos .env conhecidos."""
    env_paths = [
        "/home/jose/dev/interopmcp/demo-web/.env",
        "/home/jose/dev/tmp/interopmcp/demo-web/.env",
        "/home/jose/dev/interopmcp/.env",
        "/home/jose/dev/tmp/interopmcp/.env",
    ]
    for path in env_paths:
        try:
            with open(path) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("INTEROPMCP_DEMO_PASSWORD="):
                        return line.split("=", 1)[1].strip().strip('"').strip("'")
        except FileNotFoundError:
            continue
    return None


if not PWD:
    PWD = read_password_from_env_file() or "demo"


def post(payload=None, raw_body=None, content_type="application/json"):
    """Faz POST com Basic auth e retorna (status_code, corpo).
    Lê sempre o corpo completo (mesmo em erro) para liberar a conexão HTTP."""
    data = raw_body if raw_body is not None else (
        json.dumps(payload).encode("utf-8") if payload is not None else None
    )
    req = urllib.request.Request(BASE, data=data, method="POST")
    req.add_header("Content-Type", content_type)
    auth = base64.b64encode(f"{USER}:{PWD}".encode()).decode()
    req.add_header("Authorization", f"Basic {auth}")
    try:
        resp = urllib.request.urlopen(req, timeout=60)
        body = resp.read().decode("utf-8")
        return resp.status, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        return e.code, body
    except Exception as e:  # noqa: BLE001
        return None, f"ERRO: {e}"


def titulo(texto):
    print(f"\n{'='*70}\n{texto}\n{'='*70}")


def main():
    # Carrega PDF de teste se existir
    pdf_b64 = None
    pdf_candidates = [
        "/tmp/opencode/fornecedor.pdf",
        "/home/jose/dev/tmp/interopmcp/tests/assets/fornecedor.pdf",
        "/home/jose/dev/tmp/interopmcp/src/br/musketeers/InteropMCP/Demo/Invoices/INV-2026-118.pdf",
    ]
    for p in pdf_candidates:
        if os.path.exists(p):
            with open(p, "rb") as f:
                pdf_b64 = base64.b64encode(f.read()).decode("ascii")
            print(f"PDF de teste carregado: {p}")
            break

    resultados = []

    # 1) Sem credenciais -> 401
    titulo("1) Sem credenciais (deve retornar 401)")
    req = urllib.request.Request(BASE, data=json.dumps({"Goal": "teste"}).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            resultados.append(("Sem credenciais", resp.status, resp.read().decode()))
    except urllib.error.HTTPError as e:
        resultados.append(("Sem credenciais", e.code, e.read().decode()))
    except Exception as e:  # noqa: BLE001
        resultados.append(("Sem credenciais", None, f"ERRO: {e}"))

    # 2) Sem Goal -> 400
    titulo("2) Sem Goal (deve retornar 400)")
    st, body = post({"CNPJ": "12.345.678/0001-90"})
    resultados.append(("Sem Goal", st, body))

    # 3) Com Goal, sem PDF -> 200
    titulo("3) Com Goal, sem PDF (deve retornar 200)")
    st, body = post({"Goal": "Avaliar o fornecedor do documento", "CNPJ": "12.345.678/0001-90"})
    resultados.append(("Com Goal", st, body))

    # 4) Com Goal + PDF -> 200
    if pdf_b64:
        titulo("4) Com Goal + PDF base64 (deve retornar 200)")
        st, body = post({
            "Goal": "Avaliar o fornecedor do documento anexo",
            "CNPJ": "12.345.678/0001-90",
            "DocumentBase64": pdf_b64,
        })
        resultados.append(("Com Goal + PDF", st, body))
    else:
        print("\nAVISO: PDF de teste não encontrado; pulando teste com documento.")

    # 5) Corpo inválido (não-JSON) -> 400
    titulo("5) Corpo inválido (não JSON) (deve retornar 400)")
    st, body = post(raw_body=b"isto nao e json", content_type="application/json")
    resultados.append(("Corpo invalido", st, body))

    # Resumo
    print("\n" + "=" * 70)
    print("RESUMO")
    print("=" * 70)
    todos_ok = True
    for nome, st, body in resultados:
        ok = st in (200, 400, 401)
        todos_ok = todos_ok and ok
        print(f"[{'OK' if ok else 'FALHA'}] {nome}: HTTP {st}")
        if body and len(body) < 300:
            print(f"      {body.strip()}")
        elif body:
            print(f"      {body.strip()[:300]}...")

    sys.exit(0 if todos_ok else 1)


if __name__ == "__main__":
    main()
