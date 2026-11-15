#!/bin/bash
# Testa a API REST do agente (POST /api/agent/assess) e, opcionalmente, o MCP.
#
# Por padrão aponta para o stack de TESTE (porta 52775). Use --prod para a
# porta canônica de produção (52773).
#
# Dependências: curl e python3 (jq não é necessário).
set -euo pipefail
cd "$(dirname "$0")"

# ---------------------------------------------------------------- defaults
PROFILE="test"
HOST="localhost"
PORT=52775
MCP_PORT=8083
USER_NAME="mcp_demo"
PASSWORD="${INTEROPMCP_PWD:-}"
PDF="../src/br/musketeers/InteropMCP/Demo/Invoices/INV-2026-118.pdf"
SKIP_PDF=0
WITH_MCP=0
TIMEOUT=300
VERBOSE=0
FAIL_FAST=0

blue()   { printf "\033[1;34m%s\033[0m\n" "$*"; }
green()  { printf "\033[1;32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[1;33m%s\033[0m\n" "$*"; }
red()    { printf "\033[1;31m%s\033[0m\n" "$*"; }

usage() {
  cat <<'EOF'
Uso: ./test-api.sh [opções]

Alvo:
  --prod              usa a porta de produção (52773) e MCP 8080
                      (padrão: stack de teste, REST 52775 / MCP 8083)
  --host HOST         host (default: localhost)
  --port N            porta REST (sobrescreve o perfil)
  --mcp-port N        porta do MCP (sobrescreve o perfil)

Credenciais:
  --user U            usuário (default: mcp_demo)
  --password P        senha (default: $INTEROPMCP_PWD ou INTEROPMCP_DEMO_PASSWORD do .env)

Cenários:
  --pdf PATH          PDF a anexar (default: src/.../Invoices/INV-2026-118.pdf)
  --skip-pdf          não testa anexo de PDF
  --mcp               inclui smoke test do MCP (tools/list = 8)
  --timeout S         timeout por requisição (default: 300)
  --verbose           imprime o corpo de cada resposta
  --fail-fast         para no primeiro cenário com falha
  -h, --help          mostra esta ajuda
EOF
}

# ---------------------------------------------------------------- args
while [ $# -gt 0 ]; do
  case "$1" in
    --prod)     PROFILE="prod"; PORT=52773; MCP_PORT=8080 ;;
    --host)     HOST="$2"; shift ;;
    --port)     PORT="$2"; shift ;;
    --mcp-port) MCP_PORT="$2"; shift ;;
    --user)     USER_NAME="$2"; shift ;;
    --password) PASSWORD="$2"; shift ;;
    --pdf)      PDF="$2"; shift ;;
    --skip-pdf) SKIP_PDF=1 ;;
    --mcp)      WITH_MCP=1 ;;
    --timeout)  TIMEOUT="$2"; shift ;;
    --verbose)  VERBOSE=1 ;;
    --fail-fast) FAIL_FAST=1 ;;
    -h|--help)  usage; exit 0 ;;
    *) red "Opção desconhecida: $1"; echo; usage; exit 1 ;;
  esac
  shift
done

URL="http://${HOST}:${PORT}/api/agent/assess"
MCP_URL="http://${HOST}:${MCP_PORT}/mcp"

read_env_password() {
  local f v
  for f in ./.env ../.env; do
    [ -f "$f" ] || continue
    v=$(grep -E '^INTEROPMCP_DEMO_PASSWORD=' "$f" | tail -n1 | cut -d= -f2- || true)
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
  done
  return 1
}

if [ -z "$PASSWORD" ]; then
  if ! PASSWORD=$(read_env_password); then
    red "❌ Senha não informada e INTEROPMCP_DEMO_PASSWORD não encontrada em ./.env ou ../.env."
    red "   Use --password ou defina INTEROPMCP_PWD."
    exit 1
  fi
fi

BASIC=$(printf '%s:%s' "$USER_NAME" "$PASSWORD" | base64 -w0)

BODY_FILE=$(mktemp)
HEADER_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE" "$HEADER_FILE"' EXIT

# ---------------------------------------------------------------- http helper
# call_api <auth: valid|wrong|none> <content-type> <body>
# Imprime o HTTP status; corpo em $BODY_FILE e headers em $HEADER_FILE.
call_api() {
  local auth="$1" ctype="$2" data="$3" code
  local -a args=(
    -sS -o "$BODY_FILE" -D "$HEADER_FILE" -w '%{http_code}'
    --max-time "$TIMEOUT" -X POST "$URL" -H "Content-Type: $ctype"
  )
  case "$auth" in
    valid) args+=(-H "Authorization: Basic $BASIC") ;;
    wrong) args+=(-H "Authorization: Basic $(printf '%s:%s' "$USER_NAME" "__senha_errada__" | base64 -w0)") ;;
    none)  ;;
  esac
  code=$(curl "${args[@]}" --data-binary "$data" 2>/dev/null) || code="000"
  printf '%s' "$code"
}

json_field() {
  python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    v=d.get(sys.argv[1],"") if isinstance(d,dict) else ""
    print("" if v is None else v)
except Exception:
    print("")' "$1" < "$BODY_FILE" 2>/dev/null || true
}

response_ctype() {
  grep -i '^content-type:' "$HEADER_FILE" 2>/dev/null | tail -n1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//' || true
}

show_body() {
  [ "$VERBOSE" -eq 1 ] || return 0
  local out
  out=$(head -c 600 "$BODY_FILE" 2>/dev/null || true)
  [ -n "$out" ] && echo "      ↳ ${out}"
  return 0
}

# ---------------------------------------------------------------- result tracking
PASS=0
TOTAL=0
FAILED=0
LAST_INVOCATION=""
declare -a FAILURES=()

record() { # name ok(0/1) detail
  local name="$1" ok="$2" detail="${3:-}"
  TOTAL=$((TOTAL + 1))
  if [ "$ok" -eq 1 ]; then
    PASS=$((PASS + 1))
    printf '  \033[1;32m✔\033[0m %-38s %s\n' "$name" "$detail"
  else
    FAILED=1
    FAILURES+=("$name ($detail)")
    printf '  \033[1;31m✘\033[0m %-38s %s\n' "$name" "$detail"
    if [ "$FAIL_FAST" -eq 1 ]; then
      summary
      exit 1
    fi
  fi
}

expect_code() { # name expected actual
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    record "$name" 1 "HTTP $actual (esperado $expected)"
  else
    record "$name" 0 "HTTP $actual (esperado $expected)"
  fi
  show_body
}

summary() {
  echo
  if [ "$FAILED" -eq 0 ]; then
    green "Resumo: ${PASS}/${TOTAL} OK"
  else
    red "Resumo: ${PASS}/${TOTAL} OK — falhas:"
    local f
    for f in "${FAILURES[@]}"; do red "  - $f"; done
  fi
  [ -n "$LAST_INVOCATION" ] && echo "Última InvocationId: ${LAST_INVOCATION}"
}

# ---------------------------------------------------------------- MCP smoke
mcp_tools_count() {
  local hdr sid n
  hdr=$(mktemp)
  curl -s -D "$hdr" -o /dev/null \
    -H "Authorization: Basic $BASIC" \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' --max-time 15 -X POST \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-api","version":"1"}}}' \
    "$MCP_URL" 2>/dev/null || true
  sid=$(grep -i '^mcp-session-id:' "$hdr" | tr -d '\r' | awk '{print $2}')
  n=$(curl -s \
    -H "Authorization: Basic $BASIC" \
    -H "mcp-session-id: $sid" \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' --max-time 15 -X POST \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    "$MCP_URL" 2>/dev/null | grep -o '"name":"[^"]*"' | wc -l)
  rm -f "$hdr"
  printf '%s' "${n:-0}"
}

# ---------------------------------------------------------------- run
echo "=== Teste da API REST: ${URL} ==="
echo "    usuário: ${USER_NAME}    perfil: ${PROFILE}"
if [ "$PROFILE" = "prod" ]; then
  yellow "⚠ Perfil de PRODUÇÃO: cada POST cria uma invocação real."
fi
echo

# 1) sem credenciais
expect_code "1) sem credenciais" 401 "$(call_api none application/json '{"Goal":"teste"}')"

# 2) senha errada
expect_code "2) senha errada" 401 "$(call_api wrong application/json '{"Goal":"teste"}')"

# 3) corpo não-JSON
code=$(call_api valid application/json 'isto nao e json')
if [ "$code" = "400" ] && [ "$(json_field status)" = "failed" ]; then
  record "3) corpo não-JSON" 1 "HTTP 400 + status=failed"
else
  record "3) corpo não-JSON" 0 "HTTP $code (esperado 400 + status=failed)"
fi
show_body

# 4) JSON sem Goal
expect_code "4) JSON sem Goal" 400 "$(call_api valid application/json '{"CNPJ":"12.345.678/0001-90"}')"

# 5) Goal vazio
expect_code "5) Goal vazio" 400 "$(call_api valid application/json '{"Goal":""}')"

# 6) Goal válido
code=$(call_api valid application/json '{"Goal":"Avaliar o fornecedor do documento","CNPJ":"12.345.678/0001-90"}')
status=$(json_field Status)
inv=$(json_field InvocationId)
answer=$(json_field Answer)
if [ "$code" = "200" ] && [ -n "$status" ] && [ -n "$inv" ] && [ -n "$answer" ]; then
  LAST_INVOCATION="$inv"
  record "6) Goal válido" 1 "HTTP 200 (Status=${status})"
else
  record "6) Goal válido" 0 "HTTP $code (Status='${status}' InvocationId='${inv}')"
fi
show_body

# 9) Content-Type (aproveita os headers da chamada anterior)
ctype=$(response_ctype)
if echo "$ctype" | grep -qi 'application/json'; then
  record "9) Content-Type application/json" 1 "$ctype"
else
  record "9) Content-Type application/json" 0 "recebido: '${ctype:-<vazio>}'"
fi

# 7) Goal + PDF válido
if [ "$SKIP_PDF" -eq 1 ]; then
  yellow "  – 7) PDF: pulado (--skip-pdf)"
elif [ ! -f "$PDF" ]; then
  yellow "  – 7) PDF: pulado (arquivo não encontrado: $PDF)"
else
  b64=$(base64 -w0 "$PDF")
  payload="{\"Goal\":\"Avaliar o fornecedor do documento anexo\",\"CNPJ\":\"12.345.678/0001-90\",\"DocumentBase64\":\"${b64}\"}"
  code=$(call_api valid application/json "$payload")
  status=$(json_field Status)
  inv=$(json_field InvocationId)
  if [ "$code" = "200" ] && [ -n "$status" ] && [ -n "$inv" ]; then
    LAST_INVOCATION="$inv"
    record "7) Goal + PDF" 1 "HTTP 200 (Status=${status})"
  else
    err=$(json_field error | cut -c1-90)
    record "7) Goal + PDF" 0 "HTTP $code (${err:-Status='${status}'})"
  fi
  show_body

  # 8) DocumentBase64 inválido (depende do módulo de PDF estar disponível)
  nb64=$(printf 'isto nao e um pdf' | base64 -w0)
  code=$(call_api valid application/json "{\"Goal\":\"teste\",\"DocumentBase64\":\"${nb64}\"}")
  if [ "$code" = "400" ]; then
    record "8) DocumentBase64 inválido" 1 "HTTP 400"
  else
    record "8) DocumentBase64 inválido" 0 "HTTP $code (esperado 400)"
  fi
  show_body
fi

# 10) MCP (opcional)
if [ "$WITH_MCP" -eq 1 ]; then
  n=$(mcp_tools_count)
  if [ "$n" = "8" ]; then
    record "10) MCP tools/list" 1 "${n} ferramentas"
  else
    record "10) MCP tools/list" 0 "${n} ferramentas (esperado 8)"
  fi
fi

summary
exit "$FAILED"
