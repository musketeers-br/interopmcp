#!/bin/bash
# Reconstrói imagens e containers do demo-web SEM tocar nos endpoints ngrok.
#
# - Não inicia, não para e não mata o agente ngrok.
# - Não chama publish-ngrok.sh nem stop-ngrok.sh.
# - Mantém volumes e redes (sem "docker compose down -v").
# - Preserva IRIS_WEB_BASE: usa a URL do túnel IRIS publicado (se o ngrok
#   estiver ativo e /tmp/ngrok-endpoints.txt existir) para que os links do
#   Message Viewer / User Portal continuem apontando para o portal público.
#
# Uso: ./rebuild-demo.sh [--help]

set -euo pipefail

cd "$(dirname "$0")"

ENDPOINTS_FILE="/tmp/ngrok-endpoints.txt"
IRIS_CONTAINER="ai-hub-demo-web-iris-1"
MCP_CONTAINER="ai-hub-demo-web-mcp-launcher"

case "${1:-}" in
  --help|-h)
    echo "Uso: $0"
    echo ""
    echo "Reconstrói imagens e containers do demo-web sem tocar nos endpoints ngrok."
    echo "Endpoints são gerenciados exclusivamente por:"
    echo "  ./publish-ngrok.sh   (publica)"
    echo "  ./stop-ngrok.sh      (encerra)"
    exit 0
    ;;
  "")
    ;;
  *)
    echo "Parâmetro desconhecido: $1 (use --help)"
    exit 1
    ;;
esac

echo "==========================================="
echo "  🔄 REBUILD DEMO-WEB (imagens + containers)"
echo "     endpoints ngrok NÃO serão tocados"
echo "==========================================="
echo ""

# --- Determinar IRIS_WEB_BASE ------------------------------------------------
# Prioriza a URL do túnel IRIS publicado, mas só se o agente ngrok estiver vivo
# (evita usar um /tmp/ngrok-endpoints.txt obsoleto). Caso contrário, usa o .env.
IRIS_WEB_BASE=""
SOURCE=".env"

if [ -f "$ENDPOINTS_FILE" ] && pgrep -x ngrok >/dev/null 2>&1; then
  IRIS_WEB_BASE=$(grep '^iris=' "$ENDPOINTS_FILE" | head -n1 | cut -d= -f2- || true)
  [ -n "$IRIS_WEB_BASE" ] && SOURCE="$ENDPOINTS_FILE (túnel ngrok ativo)"
fi

if [ -z "$IRIS_WEB_BASE" ]; then
  IRIS_WEB_BASE=$(grep -E '^IRIS_WEB_BASE=' .env | tail -n1 | cut -d= -f2- || true)
fi

if [ -z "$IRIS_WEB_BASE" ]; then
  IRIS_WEB_BASE="http://localhost:52773"
  SOURCE="fallback"
fi

echo "IRIS_WEB_BASE: $IRIS_WEB_BASE"
echo "  (origem: $SOURCE)"
echo ""

if [ -f "$ENDPOINTS_FILE" ]; then
  echo "Endpoints ngrok existentes (preservados, não serão alterados):"
  sed 's/^/  /' "$ENDPOINTS_FILE"
else
  echo "Nenhum endpoint ngrok publicado ($ENDPOINTS_FILE ausente)."
fi
echo ""

export IRIS_WEB_BASE

# --- Reconstruir imagens -----------------------------------------------------
echo "=== Reconstruindo imagens (docker compose build) ==="
docker compose build

# --- Recriar containers ------------------------------------------------------
# --force-recreate garante containers novos mesmo se a imagem for idêntica
# (sem "down", portanto volumes/redes/endpoints não são afetados).
echo ""
echo "=== Recriando containers (docker compose up -d --force-recreate) ==="
docker compose up -d --force-recreate --remove-orphans

# --- Aguardar IRIS healthy ---------------------------------------------------
echo ""
echo "=== Aguardando IRIS healthy ==="
for i in $(seq 1 60); do
  STATUS=$(docker inspect -f '{{.State.Health.Status}}' "$IRIS_CONTAINER" 2>/dev/null || echo "starting")
  if [ "$STATUS" = "healthy" ]; then
    echo "IRIS healthy."
    break
  fi
  echo "Aguardando IRIS... ($i/60)"
  sleep 5
done

# --- Aguardar MCP pronto -----------------------------------------------------
echo ""
echo "=== Aguardando MCP pronto ==="
for i in $(seq 1 60); do
  STATUS=$(docker logs "$MCP_CONTAINER" 2>&1 | grep -c "4/4 checks passed" || true)
  if [ "$STATUS" -ge 1 ]; then
    echo "MCP provisionado."
    break
  fi
  echo "Aguardando MCP... ($i/60)"
  sleep 5
done

# --- Verificar backend -------------------------------------------------------
echo ""
echo "=== Verificando /api/config ==="
sleep 3
CONFIG_BASE=$(curl -s --max-time 5 http://127.0.0.1:3000/api/config 2>/dev/null \
  | python3 -c "import sys, json; print(json.load(sys.stdin).get('irisWebBase', ''))" 2>/dev/null || true)

# --- Resumo ------------------------------------------------------------------
echo ""
echo "=== Status dos containers ==="
docker compose ps

if pgrep -x ngrok >/dev/null 2>&1; then
  NGROK_STATE="ativo (não alterado)"
else
  NGROK_STATE="não está rodando (não iniciado por este script)"
fi

echo ""
echo "==========================================="
echo "  ✅ REBUILD CONCLUÍDO"
echo "==========================================="
echo "  Imagens:      reconstruídas"
echo "  Containers:   recriados (volumes/redes preservados)"
echo "  IRIS_WEB_BASE aplicado: $IRIS_WEB_BASE"
if [ -n "$CONFIG_BASE" ]; then
  echo "  /api/config irisWebBase: $CONFIG_BASE"
fi
echo "  ngrok:        $NGROK_STATE"
if [ -f "$ENDPOINTS_FILE" ]; then
  echo ""
  echo "  Endpoints públicos (inalterados):"
  sed 's/^/    /' "$ENDPOINTS_FILE"
fi
echo ""
echo "  Para publicar/encerrar endpoints use:"
echo "    ./publish-ngrok.sh   |   ./stop-ngrok.sh"
echo "==========================================="
