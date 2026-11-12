# Instruções — Gravação do Vídeo Tutorial InteropMCP (en-US)

Este documento explica como executar `record-video.mjs` para produzir o
vídeo tutorial do InteropMCP com legendas em inglês (en-US), em modo **headless**
(fiel à referência em `~/dev/sentai-task/video/promo/record-promo.mjs`).

O vídeo é um arquivo **bruto, sem mixagem** (áudio/TTS e mesclagem com a
introdução ficam para uma etapa posterior):

| Vídeo | Conteúdo | Duração alvo |
|-------|----------|--------------|
| `output/intro.mp4` | Animação HTML5 de introdução (gravada em `record-intro.mjs`) | ~80 s |
| `output/tutorial-raw.mp4` | Execução do fluxo de ferramentas do InteropMCP (legendas queimadas na gravação) | ~4–5 min |
| `output/subtitles.srt` | Legendas en-US com timestamps | — |

---

## Arquitetura

Um único contexto Playwright Chromium headless grava um "stage" servido
localmente em `http://localhost:9999/` contendo dois iframes:

| Iframe | Conteúdo | URL |
|--------|----------|-----|
| `term` | Terminal web (ttyd → Opencode CLI) | `http://localhost:7681` |
| `portal` | IRIS Message Viewer (`/ui/...`) e Workflow User Portal | `http://localhost:52773/...` (Message Viewer com `%24NAMESPACE=IRISAPP`; Workflow com `$NAMESPACE=IRISAPP`) |

O `recordVideo` grava o stage inteiro, então terminal e portal aparecem no
mesmo vídeo e são alternados conforme o fluxo. A legenda (`div#caption`, fundo
a 25% de opacidade, posicionada no **topo** para não cobrir a barra de input do
Opencode) é queimada **durante** a gravação.

O `loadPortal` aguarda o evento `framenavigated` do iframe e o `loadState('load')`
do novo documento antes de medir o conteúdo — assim o Message Viewer/Workflow
realmente navegam, sem exibir a página anterior "presa" ou em branco.

### Leitura do terminal (xterm)
O ttyd expõe a instância xterm como `window.term` no iframe `term`. O script
lê `window.term.buffer.active` via `page.frame({name:'term'}).evaluate(...)`
para:
- **Detectar término do agente**: espera o buffer ficar estável antes de trocar de view (`waitTerminalIdle`).
- **Extrair o `invocationId`** do resultado do `AccountBlock` (**último GUID** visível no terminal), usado no `GetInvocationStatus` seguinte.

---

## Pré-requisitos

### 1. ffmpeg (obrigatório)

Build estático em `/tmp/opencode/ffmpeg/ffmpeg`:

```bash
/tmp/opencode/ffmpeg/ffmpeg -version
```

Se não existir:

```bash
mkdir -p /tmp/opencode/ffmpeg
cd /tmp/opencode/ffmpeg
curl -fsSL -o ffmpeg.tar.xz "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
tar xf ffmpeg.tar.xz
cp ffmpeg-*/ffmpeg ffmpeg-*/ffprobe .
chmod +x ffmpeg ffprobe
```

### 2. Stack demo-web rodando

```bash
cd demo-web
docker compose up -d iris mcp-launcher opencode ttyd-opencode
```

Serviços esperados: `ai-hub-demo-web-iris-1` (healthy), `mcp-launcher`,
`opencode-1`, `ttyd-opencode`.

### 3. Container do terminal (ttyd)

Verifique `demo-web/docker-compose.yml` serviço `ttyd-opencode` com:

```yaml
tmpfs:
  - /tmp:nosuid,exec,size=512m
```

Se o opencode TUI sair com código 1, recriar o serviço:

```bash
cd demo-web
docker compose up -d --force-recreate ttyd-opencode
```

### 4. Node.js + Playwright

```bash
cd demo-web/scripts
node -e "import('playwright').then(() => console.log('playwright OK'))"
```

---

## Execução

Sessão opencode limpa (importante para evitar picker de MCPs aberto):

```bash
cd demo-web
docker compose restart ttyd-opencode
sleep 8
cd demo-web/scripts
node record-video.mjs
```

O que o script faz:

1. Levanta servidor estático em `http://localhost:9999/` servindo `stage.html`.
2. Autentica o portal IRIS (`_SYSTEM`/`SYS`) em contexto separado (não gravado) e copia cookies para o contexto gravado (sem "flash" de login).
3. Executa o fluxo dos passos do tutorial (en-US), alternando terminal/portal/console:
   - `PayLookup` (readonly) → **IRIS Message Viewer** (`/ui/interop/message-viewer/index.html?%24NAMESPACE=IRISAPP`).
   - `CustomerUpdate` (write) → Message Viewer (reutiliza a mesma página).
   - `AccountBlock` (critical) → `held`, aguarda aprovação.
   - Extrai o **último GUID** do terminal como `invocationId` → `GetInvocationStatus` (pending-approval).
   - **Workflow User Portal** — tarefa de aprovação nativa do IRIS.
   - **Aprovação real**: busca a aprovação **pela `InvocationId`** (não pela primeira pendente, evitando aprovações antigas) via `docker exec ... iris session` e faz `Approve`, com polling até o status virar `completed`.
   - `GetInvocationStatus` (completed).
   - `RiskCheck` CNPJ não-restrito (chamada direta) → Message Viewer.
   - `RiskCheck` CNPJ restrito → agente cria tarefa de Workflow → Workflow User Portal.
4. Converte WebM → MP4 com o ffmpeg estático.
5. Gera `subtitles.srt` (en-US).

---

## Saída esperada

Em `demo-web/output/`:

| Arquivo | Descrição |
|---------|-----------|
| `intro.mp4` | Introdução (gravada anteriormente) |
| `tutorial-raw.mp4` | Tutorial com legendas queimadas (1280×720, H.264, sem áudio) |
| `subtitles.srt` | Legendas en-US com timestamps |

(WebM temporário é removido após conversão.)

---

## Observações

- **Idioma:** todo o conteúdo (legendas, instruções) está em **en-US**.
- **Dark mode:** o portal IRIS é claro e não responde a `prefers-color-scheme`; o Chromium é iniciado com auto-dark (`--enable-features=WebContentsForceDark --blink-settings=forceDarkModeEnabled=true`) além de `colorScheme: 'dark'`, escurecendo o conteúdo de fato.
- **Conteúdo novo ao entrar na tela:** cada navegação para o portal usa um cache-buster (`_=<ts>`), garantindo que mensagens/tarefas recentes apareçam.
- **Sem ngrok:** o terminal web é apenas `127.0.0.1:7681`; nunca é publicado na internet.
- **Sem comando `/tutorial`:** os passos são digitados no chat do Opencode.
- **Sem mixagem ainda:** este script produz apenas `tutorial-raw.mp4` + `subtitles.srt`.
- **Pulados:** `/mcps`, `/status` e "listar ferramentas" — o vídeo vai direto ao uso das ferramentas.
- **Aprovação crítica:** via `docker exec ... iris session`, casando a aprovação pela `InvocationId` do AccountBlock (o User Portal tem bug para aprovar/rejeitar).
- **Produção demo:** `br.musketeers.InteropMCP.Demo.Production` é apenas um exemplo; o InteropMCP publica **qualquer** IRIS Interoperability Production cujos Business Services carreguem `AIGATEWAY`, `AIGATEWAYDESC`, `REQUESTCLASS`.

---

## Solução de problemas

| Problema | Solução |
|----------|---------|
| `ffmpeg: command not found` | Verifique `/tmp/opencode/ffmpeg/ffmpeg`. |
| Terminal em branco no vídeo | Reinicie `ttyd-opencode` (`docker compose restart ttyd-opencode`) antes de gravar. |
| Picker "MCPs" aberto engolindo digitação | Reiniciar o ttyd (sessão opencode limpa); o script não digita `/mcps`. |
| `invocationId` não extraído | O GUID deve aparecer no terminal após AccountBlock; verifique se o agente realmente executou a tool. |
| Aprovação não encontrada | O script casa a aprovação pela `InvocationId` (último GUID) e faz polling até 45 s; se não achar, verifique o console e `Approvals.ListPending`. |
| Portal mostra página antiga | O `loadPortal` aguarda `framenavigated` + `loadState('load')`; se persistir, verifique se a URL carrega (HTTP 200) e se não há `X-Frame-Options`. |
| Legendas não aparecem | Verifique `output/subtitles.srt` e a `div#caption` no stage. |
