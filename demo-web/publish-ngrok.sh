#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

PID_FILE="/tmp/ngrok-web-pids.txt"
ENDPOINTS_FILE="/tmp/ngrok-endpoints.txt"
LOG_FILE="/tmp/ngrok-web.log"
API_ADDR="127.0.0.1:4040"
IRIS_CONTAINER="ai-hub-demo-web-iris-1"
MCP_CONTAINER="ai-hub-demo-web-mcp-launcher"

if grep -q "SEU_NGROK_AUTHTOKEN_AQUI" ngrok.yml; then
  echo "⚠️  ATENÇÃO: edite ngrok.yml e insira seu authtoken real."
  echo "   Obtenha em: https://dashboard.ngrok.com/get-started/your-authtoken"
  exit 1
fi

echo "=== Parando ngrok anterior ==="
killall -9 ngrok 2>/dev/null || true
rm -f "$PID_FILE" "$ENDPOINTS_FILE"
sleep 1

echo "=== Parando containers prévios ==="
docker compose down -v 2>/dev/null || true

echo "=== Subindo infra ==="
docker compose up -d --build

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

echo "=== Iniciando ngrok (web:3000, iris:52773) ==="
nohup ngrok start --config=ngrok.yml --all > "$LOG_FILE" 2>&1 &
NGROK_PID=$!
echo "$NGROK_PID" > "$PID_FILE"
disown "$NGROK_PID" 2>/dev/null || true

# Wait for the ngrok local API and both public endpoints.
WEB_URL=""
IRIS_URL=""
for i in $(seq 1 30); do
  if ! kill -0 "$NGROK_PID" 2>/dev/null; then
    echo "❌ ngrok encerrou inesperadamente. Log:"
    cat "$LOG_FILE"
    exit 1
  fi

  JSON=$(curl -s --max-time 3 "http://${API_ADDR}/api/tunnels" 2>/dev/null || true)
  WEB_URL=$(printf '%s' "$JSON" | python3 -c "
import sys, json
try:
    for t in json.load(sys.stdin).get('tunnels', []):
        if t.get('name') == 'web':
            print(t.get('public_url', ''))
            break
except Exception:
    pass
" 2>/dev/null || true)
  IRIS_URL=$(printf '%s' "$JSON" | python3 -c "
import sys, json
try:
    for t in json.load(sys.stdin).get('tunnels', []):
        if t.get('name') == 'iris':
            print(t.get('public_url', ''))
            break
except Exception:
    pass
" 2>/dev/null || true)

  if [ -n "$WEB_URL" ] && [ -n "$IRIS_URL" ]; then
    break
  fi
  echo "Aguardando endpoints ngrok... ($i/30)"
  sleep 2
done

if [ -z "$WEB_URL" ] || [ -z "$IRIS_URL" ]; then
  echo "❌ Falha ao obter URLs do ngrok (verifique $LOG_FILE)"
  [ -n "$WEB_URL" ] && echo "   web:  $WEB_URL"
  [ -n "$IRIS_URL" ] && echo "   iris: $IRIS_URL"
  exit 1
fi

# Persist endpoint addresses (for operators and the stop script).
cat > "$ENDPOINTS_FILE" <<EOF
web=$WEB_URL
iris=$IRIS_URL
EOF

# The IRIS portal links must point at the public IRIS tunnel. Recreate the
# web container with the resolved base (the frontend reads it from /api/config).
echo "=== Aplicando IRIS_WEB_BASE=$IRIS_URL no serviço web ==="
export IRIS_WEB_BASE="$IRIS_URL"
docker compose up -d web

# Give the backend a moment, then confirm it is serving the public base.
sleep 3
CONFIG_BASE=$(curl -s --max-time 5 http://127.0.0.1:3000/api/config 2>/dev/null \
  | python3 -c "import sys, json; print(json.load(sys.stdin).get('irisWebBase', ''))" 2>/dev/null || true)

echo ""
echo "==========================================="
echo "  🎯 INTEROPMCP DEMO - ENDPOINTS PÚBLICOS"
echo "==========================================="
echo ""
echo "🌐 UI WEB (React + proxy):   $WEB_URL"
echo "🔗 IRIS PORTAL (52773):      $IRIS_URL"
echo ""
echo "   PID ngrok: $(cat "$PID_FILE")  (arquivo: $PID_FILE)"
echo "   Endereços: $ENDPOINTS_FILE"
if [ -n "$CONFIG_BASE" ]; then
  echo "   IRIS_WEB_BASE no backend: $CONFIG_BASE"
fi
echo ""
echo "🔗 Telas IRIS (pelo túnel 52773):"
echo "   Message Viewer:  ${IRIS_URL}/csp/irisapp/EnsPortal.MessageViewer.zen"
echo "   User Portal:     ${IRIS_URL}/csp/irisapp/_DeepSee.UserPortal.Workflow.zen"
echo ""
echo "✅ Publicadas apenas as portas 3000 (web) e 52773 (iris)."
echo ""
echo "📋 INSTRUÇÕES PARA AVALIADORES:"
echo "   1. Acesse a URL da UI WEB acima"
echo "   2. Digite seu prompt na caixa de texto"
echo "   3. Ou use os prompts sugeridos no Tutorial"
echo "   4. Message Viewer / User Portal abrem pelo IRIS PORTAL acima"
echo ""
echo "🛑 PARAR TUDO:"
echo "   ./demo-web/stop-ngrok.sh"
echo "==========================================="
