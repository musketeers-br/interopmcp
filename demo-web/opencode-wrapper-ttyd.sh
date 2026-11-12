#!/bin/sh
# Wrapper script for opencode startup (terminal web ttyd)
# Conecta ao mesmo InteropMCP do serviço opencode do demo-web.

# Iniciar opencode diretamente no modo terminal CLI
# Conecta ao MCP remoto configurado em /root/.opencode/opencode.json
exec opencode --log-level ERROR
