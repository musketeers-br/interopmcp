# Spec — Autenticação e Autorização do Gateway MCP (InteropMCP)

**Status:** especificação de pesquisa aprovada  
**Versão:** 1.0  
**Aplicável a:** `br.musketeers.InteropMCP` (gateway MCP sobre IRIS)  
**Autenticação alvo (Fase 1):** Basic auth por usuário do IRIS  
**TLS (Fase 1):** HTTP em loopback (local); ingress TLS da nuvem fica para Fase 2

---

## 1. Resumo

O gateway expõe o endpoint `/mcp/interopmcp` (web app Type 18, dispatch `%AI.MCP.Service`) através da bridge `iris-mcp-server` (`config_http.toml`, porta 8080). Hoje o endpoint é provisionado em modo `dev` (não autenticado) e o modo `prod` está **quebrado para Basic auth**:

- `AutheEnabled=1` é `AutheK5CCache` (bit 0, Kerberos), **não** Password. Password é bit 5 = **32**.
- `MatchRoles=":InteropMCPRoles"` **concede** a role à sessão, não restringe acesso. A restrição correta é a propriedade `Resource` da web app.
- `Security.Applications.Resource` vazio = "public application", acessível por qualquer usuário autenticado.

Esta spec define o modelo de autenticação **por usuário** (cada usuário do opencode tem credencial própria no IRIS), a autorização least-privilege no endpoint, a propagação da identidade na auditoria, o provisionamento idempotente e o plano de evolução (Fase 2: OAuth, API key, RBAC por ferramenta).

---

## 2. Contexto e problema

Fluxo atual:

```
opencode → iris-mcp-server (:8080, config_http.toml) → superserver :1972 → IRIS /mcp/interopmcp
```

- `opencode.json` remoto não envia `Authorization`.
- `config_http.toml` tem `allow_anonymous = true` e sem credenciais de endpoint.
- `Setup.Run("dev")` cria a app com `AutheEnabled=64` (unauthenticated) + `MatchRo=
les=":%All"`.
- `Setup.Run("prod")` cria com `AutheEnabled=1` (Kerberos CCache — inutilizável para Basic) + `MatchRoles=":InteropMCPRoles"` (concede a role, não restringe) e **sem `Resource`** (app pública).

Consequência: não há como hoje garantir que cada usuário do opencode apareça com sua própria identidade e credencial do IRIS.

---

## 3. Correções ao comportamento atual (evidência)

| Item | Atual (errado para Basic) | Correto | Fonte |
|------|---------------------------|---------|-------|
| `AutheEnabled` modo prod | `1` = `AutheK5CCache` (Kerberos) | `32` = `AuthePassword` | `Security.System.AutheEnabled` (Bit 5 = Password); `/api/atelier` usa `32` |
| Restrição de acesso | `MatchRoles=":InteropMCPRoles"` (concede, não restringe) | `Resource="InteropMCP_Access"` na web app | `Security.Applications.Resource`: "If no resource is defined, then it is a public application" |
| Autorização na classe | sem `RESOURCE` | `Parameter RESOURCE = "InteropMCP_Access"` | `%AI.MCP.Service.RESOURCE`: caller precisa USE em todos os recursos listados |
| Identidade na auditoria | literal `"agent"` (`Registry.cls:155,158`) | `$USERNAME` (ou `local-dev` quando não autenticado) | `Invocations.AgentIdentity` |
| Autorização `write` | no-op (`Guardrails.cls:39-41`) | validar recurso/rol (Fase 2) | `Guardrails.Check` |

Apenas Password está habilitada a nível de sistema (`Security.System.AutheEnabled = 33556471`, que inclui bit 5 = 32), então `AutheEnabled=32` funciona sem alterar o sistema.

---

## 4. Modelo de autenticação por usuário

Cada usuário do opencode se identifica com sua própria credencial do IRIS.

```
opencode (headers.Authorization: Basic base64(user:pass))
    → iris-mcp-server (encaminha Authorization as-is)
    → IRIS CSP app /mcp/interopmcp (AutheEnabled=32, valida como usuário IRIS)
    → $USERNAME / $ROLES estabelecidos pelo dispatcher
    → Guardrails / Invocations usam $USERNAME como AgentIdentity
    → Business Service executa com as permissões do usuário
```

### Por que funciona

- `iris-mcp-server` encaminha qualquer `Authorization` **as-is** para o MCP Service (`OnAuthenticate`/`ParseAuthHeader`); `Authorization` nunca fica de fora dos headers encaminhados.
- `%AI.MCP.Service` executa `OnAuthenticate` **após** a autenticação da aplicação CSP; com `AutheEnabled=32`, `$USERNAME`/`$ROLES` já estão estabelecidos quando chega ao dispatch.
- O bridge é obrigatório: o `%AI.MCP.Service` expõe `/v1/*` (REST + WebSocket), não o protocolo MCP streamable HTTP.

### Requisitos de configuração

- Web app `/mcp/interopmcp`: `AutheEnabled=32`, `Resource="InteropMCP_Access"`, `MatchRoles=""` (vazio, não concede).
- Recurso `InteropMCP_Access` criado; `InteropMCPRoles` tem `USE` sobre ele (e as permissões de banco que as tools exigem, ex.: `%DB_IRISAPP:RW` no demo).
- Cada usuário do IRIS com a role `InteropMCPRoles` (ou outro role com `USE` no recurso).
- `config_http.toml`: `allow_anonymous = false`; **sem** `endpoints[].username/password` (para não sobrescrever o header do cliente); `[[iris]] server.username/password` mantido como conta técnica do superserver.
- opencode (por usuário): `"url": "http://localhost:8080/mcp"` (local) + `"headers": { "Authorization": "{env:INTEROPMCP_BASIC}" }` (ou `{file:...}`), onde `INTEROPMCP_BASIC` já inclui o prefixo `Basic `.

### TLS (Fase 1)

- Container local: HTTP apenas em loopback, aceitável para o demo (credencial trafega localmente).
- Nuvem InterSystems: o HTTPS existente do IRIS (52773) **não cobre** a bridge (8080/8443). Deixar o TLS da nuvem/ingress para a Fase 2; nesta fase o plano assume HTTP local e documenta que a produção precisa de TLS (ingress da plataforma ou TLS nativo na bridge).

---

## 5. Modos de operação

| Modo | `AutheEnabled` | `Resource` | `MatchRoles` | `allow_anonymous` | Uso |
|------|----------------|------------|--------------|-------------------|-----|
| `dev` | `64` (unauthenticated) | vazio | `:%All` | `true` | Demo/container local, sem autenticação |
| `prod` | `32` (Password) | `InteropMCP_Access` | `""` (vazio) | `false` | Real, Basic por usuário |

Notas:
- `MatchRoles` não restringe; somente `Resource` restringe.
- Em `prod`, usuários sem `USE` em `InteropMCP_Access` recebem 403 da aplicação CSP antes de chegar ao dispatch.
- Usuários sem `Authorization` são rejeitados pela bridge (`allow_anonymous=false`) com 401/transport rejection.

---

## 6. Autorização (least privilege)

### Endpoint (Fase 1 — implementar agora)
- Aplicação CSP com `Resource="InteropMCP_Access"`.
- `%AI.MCP.Service` com `Parameter RESOURCE = "InteropMCP_Access"` (defesa em profundidade: exige `USE` em todos os recursos listados).
- `InteropMCPRoles` recebe `InteropMCP_Access:U` + permissões de banco necessárias às tools (demo: `%DB_IRISAPP:RW`; produção: mínimo necessário).

### Ferramenta (Fase 2 — não implementar agora)
- `Guardrails.Check` deve validar recurso/rol por classificação (`write`/`critical`), não apenas logar.
- Cada usuário herda as roles do IRIS; o gateway não cria usuários.

---

## 7. Identidade na auditoria

Hoje `Invocations.AgentIdentity` recebe o literal `"agent"` em todas as chamadas, tornando a auditoria inutilizável para rastrear quem executou o quê.

Mudança (Fase 1):
- Adicionar `Guardrails.CurrentAgent()`: retorna `$USERNAME` quando autenticado; `"local-dev"` quando não houver usuário (modo `dev`).
- O gerador `Registry.cls` passa `CurrentAgent()` para `Guardrails.Check` e `Invoker.Invoke` em vez de `"agent"`.
- `GetInvocationStatus` expõe `AgentIdentity` (query `InvocationStatusTools` pode ser estendida se necessário).

---

## 8. Configuração (exemplos)

### `config_http.toml` (Fase 1, local)

```toml
[[iris]]
name = "local"
server = { host = "localhost", port = 1972, username = "mcp_bridge", password = "<senha técnica>" }
endpoints = [
    { path = "/mcp/interopmcp" }
]

[mcp]
transport = "http"
port = 8080
host = "127.0.0.1"

allow_anonymous = false
```

Notas:
- `endpoints` sem `username/password`: a identidade vem do cliente.
- `allow_anonymous = false`: a bridge exige `Authorization` do cliente.
- `host = "127.0.0.1"` no container local (ou `0.0.0.0` se exposto por ingress TLS).

### `opencode.json` (por usuário)

```json
"InteropMCP": {
  "type": "remote",
  "url": "http://localhost:8080/mcp",
  "headers": { "Authorization": "{env:INTEROPMCP_BASIC}" },
  "enabled": true
}
```

O usuário define `INTEROPMCP_BASIC="Basic base64(usuario:senha)"` (ou `{file:~/.interopmcp/basic}`).

---

## 9. Provisionamento (`Setup.Run` / `EnsureSecurity`)

`Setup.Run(pMode)` chama, antes de criar/recriar a web app:

```
Setup.EnsureSecurity()
```

Idempotente:
1. `Security.Resources.Create("InteropMCP_Access", "Acesso ao endpoint MCP", "", 0)` (ou `Modify` se já existir).
2. `Security.Roles.Create("InteropMCPRoles", ..., "InteropMCP_Access:U", "")` (ou `Modify` para ajustar recursos).
3. Configura a web app:
   - `dev`: `AutheEnabled=64`, `MatchRoles=":%All"`, `Resource=""`.
   - `prod`: `AutheEnabled=32`, `MatchRoles=""`, `Resource="InteropMCP_Access"`.

Usuários de **demo** são criados pelo bootstrap da demo (ex.: `mcp_demo`, `mcp_demo2` com `InteropMCPRoles`), não pelo módulo IPM. Usuários corporativos vêm do diretório/administrador.

---

## 10. Evolução — Fase 2 (registrada em TODOs, não implementar agora)

1. **OAuth 2.0**: bridge `[oauth] iris = ...` (proxy para o IRIS como Authorization Server) + `oauth` no opencode (`opencode mcp auth`, token em `~/.local/share/opencode/mcp-auth.json`).
2. **API key customizada**: aplicação CSP em `Unauthenticated` + `OnAuthenticate` custom + `forward_headers` na bridge.
3. **RBAC por ferramenta**: `Guardrails.Check` consulta `$ROLES`/recurso por classificação (`write`/`critical`).
4. **LDAP/SSO**: diretório de usuários externo.
5. **TLS corporativo / reverse proxy**: quando a nuvem não permitir expor a porta da bridge.

---

## 11. Critérios de aceitação (Fase 1)

- [ ] `Setup.Run("prod")` cria a app com `AutheEnabled=32`, `Resource="InteropMCP_Access"`, `MatchRoles=""`.
- [ ] Recurso `InteropMCP_Access` existe; `InteropMCPRoles` tem `USE` sobre ele.
- [ ] Usuário sem `Authorization` → 401 (bridge) / rejeição.
- [ ] Usuário sem `USE` em `InteropMCP_Access` → 403 da aplicação CSP.
- [ ] Dois usuários distintos → `Invocations.AgentIdentity` distintos (`$USERNAME`), não `"agent"`.
- [ ] Usuário autenticado com a role executa tools (`readonly` e `write`) com sucesso.
- [ ] `MCPService` tem `Parameter RESOURCE = "InteropMCP_Access"`.
- [ ] `config_http.toml` com `allow_anonymous=false` e sem credenciais estáticas de endpoint.
- [ ] Demo usa `Run("prod")` com usuários de teste e credencial no opencode.
- [ ] Documentação atualizada (`authentication.md`, `architecture.md`, `README.md`, `troubleshooting.md`, `quickstart.md`, `specs/tasks.md` T042 corrigido: Password = 32, não 1).

---

## 12. Arquivos envolvidos (Fase 1)

- `src/br/musketeers/InteropMCP/Setup.cls` — `Run` + `EnsureSecurity`.
- `src/br/musketeers/InteropMCP/MCPService.cls` — `Parameter RESOURCE`.
- `src/br/musketeers/InteropMCP/Registry.cls` — gerador passa `CurrentAgent()`.
- `src/br/musketeers/InteropMCP/Guardrails.cls` — `CurrentAgent()`.
- `src/br/musketeers/InteropMCP/GeneratedTools.cls` — regenerado (não editar manualmente).
- `config_http.toml` — `allow_anonymous=false`, sem endpoint creds, TLS conforme destino.
- `docker-compose.yml` — porta/expôs conforme decisão de TLS.
- `opencode.json` — `headers.Authorization` por usuário.
- `iris.script`, `bootstrap-gateway.script` — `Run("prod")`.
- `.env.example` (placeholders versionados) e `.env` (valores reais, gitignored) — `WG_*`, `INTEROPMCP_MODE`, `INTEROPMCP_DEMO_PASSWORD`.
- `~/.bashrc` (ambiente do shell que lança o opencode) — exporta `INTEROPMCP_BASIC` a partir do `.env`; fica **fora da imagem** (rebuild não o atualiza).
- `docs/interop-mcp/authentication.md` (novo) + ajustes em `architecture.md`, `README.md`, `troubleshooting.md`, `quickstart.md`, `specs/001-interop-mcp/tasks.md`, `specs/001-interop-mcp/spec.md`.
- `specs/001-interop-mcp/data-model.md` — documentar `AgentIdentity` como identidade autenticada.

---

## 13. Sincronização da credencial do cliente (`.bashrc` + `.env*`)

A credencial do cliente MCP vive em **quatro** pontos que precisam mudar juntos. Alterar só o
`opencode.json` (ou só o bootstrap) deixa o cliente autenticando com valor ausente/errado:

1. `opencode.json` — `headers.Authorization: "{env:INTEROPMCP_BASIC}"`.
2. `.env.example` — placeholders documentados (versionado; base de um clone novo).
3. `.env` — valor real local (gitignored).
4. `~/.bashrc` (ou o shell que lança o opencode) — exporta `INTEROPMCP_BASIC`; **é o ambiente
   que o processo do opencode herda no start**.

Por que o `~/.bashrc` é obrigatório: `{env:INTEROPMCP_BASIC}` é interpolado a partir do
ambiente do **processo** quando o opencode inicia. Um `export` digitado numa sessão
transitória não sobrevive a um novo terminal nem ao restart do cliente; sem a variável a
bridge recebe a requisição sem `Authorization` e responde 401 — sintoma típico
`InteropMCP Failed to get tools` / `server unavailable`.

Por que **rebuild não corrige**: `~/.bashrc` e `.env` não estão na imagem Docker. O rebuild
recria IRIS/bridge/catálogo, mas o cliente continua sem a variável.

Regra: ao mudar o contrato de autenticação (nome da env, formato do header, rotação de
senha), atualize os quatro pontos, abra um **novo terminal** e reinicie o opencode.

Checklist de verificação:

```bash
printenv INTEROPMCP_BASIC   # deve imprimir "Basic <base64>"
```

Bloco sugerido para `~/.bashrc` (deriva do `.env` do repo, sem segredo hard-coded):

```bash
if [ -f /home/jose/dev/interopmcp/.env ]; then
  _demo_pw=$(grep -m1 '^INTEROPMCP_DEMO_PASSWORD=' /home/jose/dev/interopmcp/.env | cut -d= -f2-)
  [ -n "$_demo_pw" ] && export INTEROPMCP_BASIC="Basic $(printf 'mcp_demo:%s' "$_demo_pw" | base64 -w0)"
  unset _demo_pw
fi
```

Nota: `INTEROPMCP_BASIC` **não** é lido pelo container — é variável client-side apenas.
