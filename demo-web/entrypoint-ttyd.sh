#!/bin/sh
set -e

# Garantir que o opencode.json exista no volume (montado sobre /root/.opencode)
# Sempre sobrescreve para garantir que a config esteja atualizada
mkdir -p /root/.opencode
cp /app/opencode.json /root/.opencode/opencode.json

# Desativar verificação de atualização do opencode para evitar mensagens no terminal
export OPENCODE_DISABLE_UPDATE_CHECK=true
export OPENCODE_NO_UPDATE_CHECK=true
export OPENCODE_AUTO_UPDATE=false
export OPENCODE_UPDATE_CHECK=false
export OPENCODE_UPDATE_CHECK_DISABLED=true
export DISABLE_UPDATE_CHECK=true
export NO_UPDATE_CHECK=true
export CHECK_FOR_UPDATES=false
export OPENCODE_NO_UPDATE=true
export DISABLE_UPDATE_NOTIFICATION=true
export OPENCODE_UPDATE_CHECK_ENABLED=false
export DISABLE_SELF_UPDATE=true
export SKIP_UPDATE_CHECK=true

# Iniciar ttyd com o wrapper script que exibe mensagem de boas-vindas
# Bind a 0.0.0.0 dentro do container; o docker-compose restringe o acesso
# ao host apenas em 127.0.0.1:7681 (nunca exposto além do localhost).
exec ttyd -p 7681 -i 0.0.0.0 /app/opencode-wrapper-ttyd.sh
