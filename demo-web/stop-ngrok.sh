#!/bin/bash

PID_FILE="/tmp/ngrok-web-pids.txt"
ENDPOINTS_FILE="/tmp/ngrok-endpoints.txt"

echo "=== Endpoints publicados ==="
if [ -f "$ENDPOINTS_FILE" ]; then
  cat "$ENDPOINTS_FILE"
else
  echo "(arquivo $ENDPOINTS_FILE não encontrado)"
fi

echo ""
echo "=== Parando ngrok ==="
PIDS=()
if [ -f "$PID_FILE" ]; then
  while IFS= read -r line; do
    pid=$(printf '%s' "$line" | tr -d '[:space:]')
    [ -n "$pid" ] && PIDS+=("$pid")
  done < "$PID_FILE"
fi

if [ ${#PIDS[@]} -eq 0 ]; then
  echo "Nenhum PID salvo em $PID_FILE; usando fallback killall."
else
  # Graceful shutdown first.
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "SIGTERM -> PID $pid"
      kill "$pid" 2>/dev/null || true
    else
      echo "PID $pid já não está rodando."
    fi
  done

  # Wait up to 10s for all tracked PIDs to exit.
  for i in $(seq 1 10); do
    alive=0
    for pid in "${PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then alive=1; fi
    done
    [ "$alive" -eq 0 ] && break
    sleep 1
  done

  # Force-kill whatever is still alive.
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "SIGKILL -> PID $pid"
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
fi

# Clean up any orphan agent not tracked by the PID file.
if pgrep -x ngrok >/dev/null 2>&1; then
  echo "Encerrando processos ngrok remanescentes..."
  killall -9 ngrok 2>/dev/null || true
fi

# Verify that nothing survived.
sleep 1
if pgrep -x ngrok >/dev/null 2>&1; then
  echo "❌ Ainda há processos ngrok rodando:"
  pgrep -a -x ngrok
  NGrok_ALIVE=1
else
  echo "✅ Nenhum processo ngrok remanescente."
  NGrok_ALIVE=0
fi

rm -f "$PID_FILE" "$ENDPOINTS_FILE"

echo "=== Parando containers ==="
cd "$(dirname "$0")"
docker compose down -v 2>/dev/null || true

if [ "$NGrok_ALIVE" -eq 1 ]; then
  echo "⚠️  Containers parados, mas processos ngrok sobreviveram."
  exit 1
fi

echo "✅ Tudo parado."
