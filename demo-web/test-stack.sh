#!/bin/bash
# Sobe/derruba um ambiente de teste paralelo (projeto demo-web-test) sem
# tocar nos containers de produção (projeto demo-web).
#
# Uso: ./test-stack.sh {up|down|status|logs}
set -euo pipefail
cd "$(dirname "$0")"

PROJECT="demo-web-test"
PROD_PROJECT="demo-web"
PROD_IRIS="ai-hub-demo-web-iris-1"
IRIS_TEST="ai-hub-demo-web-iris-test-1"
COMPOSE=(docker compose -p "$PROJECT" -f docker-compose.yml -f docker-compose.test.yml)

PORT_WEB=3002
PORT_OPENCODE=3032
PORT_TTYD=7683
PORT_IRIS=52775
PORT_MCP=8083

blue()   { printf "\033[1;34m%s\033[0m\n" "$*"; }
green()  { printf "\033[1;32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[1;33m%s\033[0m\n" "$*"; }

if [ "$PROJECT" = "$PROD_PROJECT" ]; then
  yellow "❌ O projeto de teste não pode ser igual ao de produção ($PROD_PROJECT)."
  exit 1
fi

port_busy() { timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$1" 2>/dev/null; }

port_owned_by_test() {
  docker ps --filter "label=com.docker.compose.project=$PROJECT" \
    --format '{{.Ports}}' | grep -q ":$1->"
}

preflight() {
  command -v docker >/dev/null 2>&1 || { yellow "❌ docker não encontrado no PATH."; exit 1; }
  docker info >/dev/null 2>&1 || { yellow "❌ O daemon do Docker não está rodando."; exit 1; }
  [ -f docker-compose.test.yml ] || { yellow "❌ docker-compose.test.yml ausente."; exit 1; }
  [ -f .env ] || { yellow "❌ .env ausente."; exit 1; }

  local p
  for p in "$PORT_WEB" "$PORT_OPENCODE" "$PORT_TTYD" "$PORT_IRIS" "$PORT_MCP"; do
    if port_busy "$p" && ! port_owned_by_test "$p"; then
      yellow "❌ Porta $p já está em uso (produção?). Abortando para não colidir."
      exit 1
    fi
  done
}

wait_healthy() {
  blue "Aguardando o IRIS de teste ficar healthy..."
  local i status
  for i in $(seq 1 60); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$IRIS_TEST" 2>/dev/null || echo starting)
    if [ "$status" = "healthy" ]; then
      green "✔ IRIS de teste healthy."
      return 0
    fi
    sleep 3
  done
  yellow "⚠ Timeout aguardando o IRIS de teste. Veja: $0 logs"
  exit 1
}

wait_mcp() {
  blue "Aguardando o bridge MCP registrar as ferramentas..."
  local i
  for i in $(seq 1 40); do
    if docker exec "$IRIS_TEST" sh -c 'grep -q "Service local_mcp_interopmcp registered" /tmp/mcp.log 2>/dev/null'; then
      green "✔ Bridge MCP pronto."
      return 0
    fi
    sleep 2
  done
  yellow "⚠ O bridge ainda não registrou ferramentas. Veja: $0 logs"
}

demo_password() {
  grep -E '^INTEROPMCP_DEMO_PASSWORD=' .env | cut -d= -f2- || true
}

print_urls() {
  local pwd_val basic
  pwd_val=$(demo_password)
  basic=$(printf 'mcp_demo:%s' "$pwd_val" | base64 -w0)

  echo
  green "============================================================"
  green "  AMBIENTE DE TESTE NO AR — PRODUÇÃO INTOCADA"
  green "============================================================"
  echo "  Aplicação (frontend):  http://localhost:${PORT_WEB}"
  echo "  Terminal (opencode):   http://localhost:${PORT_TTYD}"
  echo "  OpenCode server:       http://localhost:${PORT_OPENCODE}"
  echo "  IRIS Portal:           http://localhost:${PORT_IRIS}/csp/sys/UtilHome.csp"
  echo "  IRIS MCP (host):       http://localhost:${PORT_MCP}/mcp"
  echo "  REST API:              http://localhost:${PORT_IRIS}/api/agent/assess"
  echo
  echo "  Credenciais (do .env): mcp_demo / ${pwd_val}"
  echo "  (na rede de teste o opencode usa http://iris:8080/mcp)"
  echo
  echo "  Teste rápido REST:"
  echo "    curl -s -X POST http://localhost:${PORT_IRIS}/api/agent/assess \\"
  echo "      -H 'Authorization: Basic ${basic}' \\"
  echo "      -H 'Content-Type: application/json' \\"
  echo "      -d '{\"Goal\":\"Avaliar\",\"CNPJ\":\"12.345.678/0001-90\"}'"
  echo
  echo "  Logs: $0 logs     Status: $0 status     Derrubar: $0 down"
}

up() {
  preflight

  local before after
  before=$(docker inspect -f '{{.State.StartedAt}}' "$PROD_IRIS" 2>/dev/null || echo n/a)

  blue "Subindo stack de teste (projeto ${PROJECT}) com rebuild..."
  # --always-recreate-deps: quando o iris é recriado (imagem nova), o
  # mcp-launcher também precisa ser recriado para rodar de novo o
  # bootstrap-gateway.script (provisiona /api/agent e o gateway /mcp) e
  # iniciar um mcp-server limpo.
  IRIS_WEB_BASE="http://localhost:${PORT_IRIS}" "${COMPOSE[@]}" up -d --build --always-recreate-deps

  wait_healthy
  wait_mcp

  after=$(docker inspect -f '{{.State.StartedAt}}' "$PROD_IRIS" 2>/dev/null || echo n/a)
  if [ "$before" = "$after" ]; then
    green "✔ Produção intocada (uptime preservado)."
  else
    yellow "⚠ ATENÇÃO: o container de produção ${PROD_IRIS} foi reiniciado!"
  fi

  print_urls
}

down() {
  blue "Derrubando ambiente de teste (projeto ${PROJECT}) e removendo volumes..."
  "${COMPOSE[@]}" down --volumes || true
  green "✔ Ambiente de teste removido. Produção não foi alterada."
}

status() {
  echo "== Teste (projeto ${PROJECT}) =="
  docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
    --format '  {{.Names}}\t{{.Status}}\t{{.Ports}}'
  echo "== Produção (projeto ${PROD_PROJECT}) =="
  docker ps --filter "label=com.docker.compose.project=$PROD_PROJECT" \
    --format '  {{.Names}}\t{{.Status}}'
}

logs() {
  docker exec "$IRIS_TEST" sh -c 'tail -n 60 /tmp/mcp.log' 2>/dev/null \
    || "${COMPOSE[@]}" logs --tail=60
}

case "${1:-}" in
  up)     up ;;
  down)   down ;;
  status) status ;;
  logs)   logs ;;
  *)
    echo "Uso: $0 {up|down|status|logs}"
    exit 1
    ;;
esac
