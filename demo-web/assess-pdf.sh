#!/bin/bash
# Chama o agente (POST /api/agent/assess) passando um PDF.
#
# Versão simplificada do test-api.sh: faz apenas um cenário — Goal + PDF.
# O prompt (Goal) é enviado em en-US.
#
# Dependências: curl, base64, python3 (para parsear a resposta).
set -euo pipefail
cd "$(dirname "$0")"

# ---------------------------------------------------------------- defaults
HOST="localhost"
PORT=52775
USER_NAME="mcp_demo"
PASSWORD="${INTEROPMCP_PWD:-}"
PDF="../src/br/musketeers/InteropMCP/Demo/Invoices/INV-2026-118.pdf"
TIMEOUT=300
VERBOSE=0
CNPJ=""

URL="http://${HOST}:${PORT}/api/agent/assess"

# ---------------------------------------------------------------- args
usage() {
  cat <<'EOF'
Uso: ./assess-pdf.sh [opções]

  --host HOST      host (default: localhost)
  --port N         porta REST (default: 52775)
  --user U         usuário (default: mcp_demo)
  --password P     senha (default: $INTEROPMCP_PWD ou INTEROPMCP_DEMO_PASSWORD no .env)
  --pdf PATH       PDF a anexar (default: INV-2026-118.pdf)
  --cnpj CNPJ      CNPJ do fornecedor (default: vazio - o agente extrai do PDF)
  --timeout S      timeout por requisição (default: 300)
  --verbose        imprime o corpo bruto da resposta
  -h, --help       mostra esta ajuda
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host)     HOST="$2"; shift ;;
    --port)     PORT="$2"; shift ;;
    --user)     USER_NAME="$2"; shift ;;
    --password) PASSWORD="$2"; shift ;;
    --pdf)      PDF="$2"; shift ;;
    --cnpj)     CNPJ="$2"; shift ;;
    --timeout)  TIMEOUT="$2"; shift ;;
    --verbose)  VERBOSE=1 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Opção desconhecida: $1"; echo; usage; exit 1 ;;
  esac
  shift
done

URL="http://${HOST}:${PORT}/api/agent/assess"

# ---------------------------------------------------------------- senha
if [ -z "$PASSWORD" ]; then
  for f in ./.env ../.env; do
    [ -f "$f" ] || continue
    v=$(grep -E '^INTEROPMCP_DEMO_PASSWORD=' "$f" | tail -n1 | cut -d= -f2- || true)
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    if [ -n "$v" ]; then PASSWORD="$v"; break; fi
  done
fi

if [ -z "$PASSWORD" ]; then
  echo "❌ Senha não informada e INTEROPMCP_DEMO_PASSWORD não encontrada em ./.env ou ../.env."
  echo "   Use --password ou defina INTEROPMCP_PWD."
  exit 1
fi

# ---------------------------------------------------------------- PDF
if [ ! -f "$PDF" ]; then
  echo "❌ PDF não encontrado: $PDF"
  exit 1
fi

# ---------------------------------------------------------------- auth + payload
BASIC=$(printf '%s:%s' "$USER_NAME" "$PASSWORD" | base64 -w0)
b64=$(base64 -w0 "$PDF")

# Prompt em en-US.
# O CNPJ do fornecedor só vai no pedido quando o chamador o informa: por
# omissão o agente extrai o fornecedor do documento anexado, e um CNPJ fixo
# aqui pode apontar para uma empresa diferente da que esta na fatura.
if [ -n "$CNPJ" ]; then
  PAYLOAD=$(printf '{"Goal":"Evaluate the supplier of the attached document","CNPJ":"%s","DocumentBase64":"%s"}' "$CNPJ" "$b64")
else
  PAYLOAD=$(printf '{"Goal":"Evaluate the supplier of the attached document","DocumentBase64":"%s"}' "$b64")
fi

# ---------------------------------------------------------------- chamada
BODY_FILE=$(mktemp)
HEADER_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE" "$HEADER_FILE"' EXIT

echo "=== Chamada ao agente: ${URL} ==="
echo "    usuário: ${USER_NAME}    PDF: ${PDF}"
echo

CODE=$(curl -sS -o "$BODY_FILE" -D "$HEADER_FILE" -w '%{http_code}' \
  --max-time "$TIMEOUT" -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $BASIC" \
  --data-binary "$PAYLOAD" 2>/dev/null) || CODE="000"

echo "HTTP status: $CODE"

if [ "$CODE" = "200" ]; then
  if [ "$VERBOSE" -eq 1 ]; then
    cat "$BODY_FILE"
  else
    python3 -c 'import sys,json
d=json.load(sys.stdin)
print("Status:", d.get("Status",""))
print("InvocationId:", d.get("InvocationId",""))
print("Answer:", d.get("Answer",""))' < "$BODY_FILE"
  fi
  exit 0
else
  echo "❌ Falha na chamada ao agente."
  if [ "$VERBOSE" -eq 1 ]; then
    cat "$BODY_FILE"
  else
    python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print("Error:", d.get("error",""))
    print("Status:", d.get("Status",""))
except Exception:
    print(sys.stdin.read()[:500])' < "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE"
  fi
  echo
  exit 1
fi
