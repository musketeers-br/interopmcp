# Instruções — Captura de telas do Tutorial InteropMCP (en-US)

Este documento explica como executar `record-screenshots.mjs` para produzir as
imagens (PNG) do tutorial do InteropMCP usadas em
`docs/articles/article-1-idea-ai-hub-tutorial.md`.

Mesmos mecanismos de `record-video.mjs` (stage com iframes, login do portal em
contexto separado, leitura do buffer do xterm), mas **sem vídeo**: cada passo
produz um PNG em `docs/articles/img/`.

| Arquivo | Descrição |
|---------|-----------|
| `demo-web/scripts/record-screenshots.mjs` | Script de captura (Playwright + Chromium headless) |
| `docs/articles/img/article-1-step-<nn>-<slug>.png` | Imagens geradas (1324×736) |

O padrão de nome segue o convencionado em `docs/articles/article-writer-agent.md`:
`article-<n>-step-<nn>-<slug>.png`.

---

## Pré-requisitos

1. **Stack demo-web rodando**:

   ```bash
   cd demo-web
   docker compose up -d iris mcp-launcher opencode ttyd-opencode
   ```

   Serviços esperados: `ai-hub-demo-web-iris-1` (healthy), `mcp-launcher`,
   `opencode-1`, `ttyd-opencode`.

2. **Node.js + Playwright** (em `demo-web/scripts`):

   ```bash
   cd demo-web/scripts
   node -e "import('playwright').then(() => console.log('playwright OK'))"
   ```

3. **Sessão opencode limpa** (evita o picker de MCPs engolindo a digitação):

   ```bash
   cd demo-web
   docker compose restart ttyd-opencode
   sleep 8
   ```

---

## Execução

```bash
cd demo-web/scripts
npm run screenshots
```

ou diretamente:

```bash
cd demo-web/scripts
node record-screenshots.mjs
```

### Opções

| Flag | Efeito |
|------|--------|
| `--no-clean` | Não rejeita aprovações pendentes nem limpa a inbox do Workflow antes de capturar. |
| `--keep-open` | Não fecha o browser ao final (útil para depurar). |

### O que o script faz

1. **Limpa o estado anterior** (a menos de `--no-clean`): rejeita as aprovações
   pendentes e esvazia a inbox do Workflow — a inbox aparece nas imagens.
2. Autentica o portal IRIS (`_SYSTEM`/`SYS`) em contexto separado (não
   gravado) e copia os cookies para o contexto de captura (sem "flash" de login).
3. Abre o terminal (ttyd → Opencode CLI) e o User Portal do Workflow.
4. Executa o fluxo do artigo:
   - `AccountBlock` (crítica) → fica **held**; `GetInvocationStatus` →
     `pending-approval`.
   - **Rejeita** no User Portal (selecionar a task → `Accept` → `Reject`) →
     `GetInvocationStatus` → `rejected`.
   - `RiskCheck` com CNPJ restrito → nova task de Workflow → **aprova** no
     portal (`Accept` → `Approve`) → a mensagem entra na produção e o status
     vira `completed`.
5. Grava um PNG por passo em `docs/articles/img/`.

---

## Saída esperada

12 imagens em `docs/articles/img/`:

| Passo | Arquivo |
|-------|---------|
| 5 | `article-1-step-05-opencode-accountblock.png` |
| 5 | `article-1-step-05-opencode-accountblock-user-portal.png` |
| 6 | `article-1-step-06-opencode-status.png` |
| 7 | `article-1-step-07-workflow-portal-inbox.png` |
| 7 | `article-1-step-07-workflow-portal-owned.png` |
| 7 | `article-1-step-07-workflow-portal-rejected.png` |
| 7 | `article-1-step-07-reject.png` |
| 8 | `article-1-step-08-restricted-riskcheck.png` |
| 8 | `article-1-step-08-workflow-task.png` |
| 8 | `article-1-step-08-workflow-portal-approved.png` |
| 8 | `article-1-step-08-restricted-riskcheck-msg.png` |
| 8 | `article-1-step-08-opencode-status.png` |

---

## Observações

- **Idioma:** os contextos do Playwright usam `locale: 'en-US'` — sem isso o
  portal IRIS renderiza em português ("Aprovar"/"Rejeitar").
- **Dark mode:** o portal IRIS é claro e não responde a `prefers-color-scheme`;
  o Chromium sobe com auto-dark (`--enable-features=WebContentsForceDark`).
- **IDs:** a fonte autoritativa dos `InvocationId`/`ApprovalId` é o **IRIS**
  (`SELECT TOP 1 ... WHERE Decision='pending' ORDER BY ID DESC`). O texto do
  TUI é apenas uma checagem: o terminal estreito pode quebrar o GUID em duas
  linhas e a extração por rótulo falhar.
- **`iris session` sem blocos:** o modo terminal executa linha a linha e **não
  aceita `{ }`** (`While ... { }` dá `<SYNTAX>`). Os laços ficam no JavaScript.

---

## Solução de problemas

| Problema | Solução |
|----------|---------|
| Terminal em branco | Reinicie `ttyd-opencode` antes de capturar. |
| Picker "MCPs" engolindo a digitação | Reinicie o ttyd (sessão opencode limpa). |
| Botões em português no portal | Os contextos precisam de `locale: 'en-US'`. |
| A task não aparece na inbox | A task é criada quando a tool crítica é retida; o script recarrega o portal com cache-buster antes de selecionar. |
| A task não some após o clique | O ZEN abre um `confirm()`: sem `page.on('dialog')` o Playwright dispensa o diálogo e a ação não acontece. |
| `aprovacao pendente nao encontrada` | A tool crítica não chegou a ser retida; verifique `Approvals.ListPending` no IRIS. |
