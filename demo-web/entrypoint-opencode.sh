#!/bin/sh
set -e

# Garantir que o opencode.json exista no volume
if [ ! -f /root/.opencode/opencode.json ]; then
    mkdir -p /root/.opencode
    cp /app/opencode.json /root/.opencode/opencode.json
fi

# Desativar verificação de atualização
export OPENCODE_DISABLE_UPDATE_CHECK=true
export OPENCODE_NO_UPDATE_CHECK=true
export OPENCODE_AUTO_UPDATE=false

# Iniciar opencode em modo web (backend para proxy via shell)
exec opencode web --port 3030 --hostname 0.0.0.0
