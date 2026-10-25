# MCP Auto-Start – Alterações realizadas

## Objetivo
Subir o servidor MCP HTTP automaticamente com o container IRIS, sem alterar o entrypoint do IRIS, e expor o servidor no OpenCode.

## Alterações aplicadas

### 1. Symlink de compatibilidade
* Criado symlink `config.toml -> config_http.toml` no repo para compatibilidade com README.
```bash
ln -s config_http.toml /home/jose/dev/ai-hub-dev-template/config.toml
```

### 2. docker-compose.yml
* **Healthcheck do serviço iris**
  ```yaml
  healthcheck:
    test: ["CMD-SHELL", "bash -c 'echo > /dev/tcp/localhost/1972'"]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 30s
  ```
* **Serviço mcp-launcher**
  * Imagem leve `docker:24-cli` com acesso ao Docker socket
  * `depends_on` iris com `condition: service_healthy`
  * Executa dentro do container IRIS via `docker exec`:
    1. `iris session IRIS 'zn "IRISAPP"; do ##class(Sample.MCPSetup).Run()'`
    2. `iris-mcp-server -c /home/irisowner/dev/config_http.toml run > /tmp/mcp.log 2>&1`
  * Não altera entrypoint do IRIS e evita duplicação de imagem.

### 3. opencode.json
Adicionado MCP remoto HTTP:
```json
"mcp-http": {
  "type": "remote",
  "url": "http://localhost:8080/mcp/sample",
  "enabled": true
}
```
Tipo corrigido de `http` para `remote` conforme documentação do OpenCode.

### 4. Validação
* `docker compose up -d`
* Container `ai-hub-dev-template-iris-1` healthy
* Processo `iris-mcp-server` rodando dentro do IRIS
* `Security.Applications /mcp/sample` Type 18, Enabled true
* `python3 test_mcp.py` lista tools `AddPerson` e `GetPeopleYoungerThan` sem Broken pipe
* OpenCode lista `mcp-http` e consegue descobrir tools

## Arquivos modificados
* `/home/jose/dev/ai-hub-dev-template/docker-compose.yml`
* `/home/jose/dev/ai-hub-dev-template/opencode.json`
* Symlink `/home/jose/dev/ai-hub-dev-template/config.toml`

## Notas
* Apenas 1 instância IRIS. O MCP roda como processo filho dentro do mesmo container via `docker exec`.
* Stdio permanece opcional in-container. Para uso no host, usar transporte HTTP.
* O launcher garante que `Sample.MCPSetup.Run()` seja executado a cada boot.
