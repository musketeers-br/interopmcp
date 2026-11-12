#!/usr/bin/env node
/**
 * record-video.mjs — Grava o tutorial do InteropMCP (en-US) em headless.
 *
 * Arquitetura (fiel a ~/dev/sentai-task/video/promo/record-promo.mjs):
 *   - Um único contexto Playwright Chromium headless com recordVideo (1280x720).
 *   - Um "stage" servido localmente em http://localhost:9999 contendo dois iframes:
 *       * ttyd (http://localhost:7681) — agente opencode
 *       * portal IRIS (http://localhost:52773/...) — portal e Workflow
 *   - Legendas queimadas durante a gravação (div#caption, fundo a 25%).
 *   - Autenticação do portal feita em um contexto separado (não gravado) e os
 *     cookies copiados para o contexto gravado (evita "flash" de login).
 *   - Aprovacao/rejeicao CRITICA feita no proprio IRIS User Portal (Workflow):
 *     a task e selecionada na inbox, o operador assume a-posse (Accept) e
 *     decide (Approve/Reject) — o ZEN abre um confirm(), tratado via page.on('dialog').
 *   - Consultas reais ao IRIS via "docker exec ... iris session" para casar a
 *     aprovacao pela InvocationId e conferir o status da invocacao.
 *
 * Produz:
 *   output/tutorial-raw.mp4  — video bruto com legendas queimadas (sem mixagem)
 *   output/subtitles.srt     — legendas en-US com timestamps
 *
 * Uso: node record-video.mjs
 */

import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { mkdirSync, existsSync, writeFileSync, readFileSync, unlinkSync } from 'fs';
import { execFileSync, spawn } from 'child_process';
import { chromium } from 'playwright';
import http from 'http';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SCRIPT_DIR = __dirname;
const OUTPUT_DIR = join(SCRIPT_DIR, '..', 'output');
const STAGE_HTML = join(SCRIPT_DIR, 'stage.html');
const STAGE_PORT = 9999;
const STAGE_URL = `http://localhost:${STAGE_PORT}/`;

const WIDTH = 1280;
const HEIGHT = 720;
const FFMPEG = '/tmp/opencode/ffmpeg/ffmpeg';

// URLs
const TTYD_URL = 'http://localhost:7681/';
const PORTAL_BASE = 'http://localhost:52773';
const PORTAL_LOGIN_URL = `${PORTAL_BASE}/csp/irisapp/EnsPortal.MessageViewer.zen`;
const INTEROP_EDITOR_URL = `${PORTAL_BASE}/ui/interop/interop-editor/index.html?%24NAMESPACE=IRISAPP&%24PRODUCTION=br.musketeers.InteropMCP.Demo.Production`;
const MESSAGE_VIEWER_URL = `${PORTAL_BASE}/ui/interop/message-viewer/index.html?%24NAMESPACE=IRISAPP`;
const WORKFLOW_URL = `${PORTAL_BASE}/csp/irisapp/_DeepSee.UserPortal.Workflow.zen?$NAMESPACE=IRISAPP`;

const USER = '_SYSTEM';
const PASS = 'SYS';
const CONTAINER = 'ai-hub-demo-web-iris-1';

// ---------- util ----------

function log(...args) {
  const ts = new Date().toISOString().replace(/T/, ' ').substring(0, 19);
  console.log(`[${ts}]`, ...args);
}

function run(cmd, args = [], opts = {}) {
  log('$', cmd, args.join(' '));
  return execFileSync(cmd, args, { stdio: 'inherit', encoding: 'utf8', ...opts });
}

function ffmpeg(args, opts = {}) {
  return run(FFMPEG, args, opts);
}

function ensureDir(p) {
  if (!existsSync(p)) mkdirSync(p, { recursive: true });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// ---------- mini servidor estatico para o stage ----------

function startStaticServer() {
  const stageContent = readFileSync(STAGE_HTML, 'utf8');
  const server = http.createServer((req, res) => {
    const url = req.url === '/' || req.url === '/stage.html' ? STAGE_HTML : null;
    if (!url) {
      res.writeHead(404); res.end('not found'); return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(stageContent);
  });
  return new Promise((resolve, reject) => {
    server.listen(STAGE_PORT, '127.0.0.1', (err) => {
      if (err) return reject(err);
      log('Servidor estatico:', STAGE_URL);
      resolve(server);
    });
  });
}

// ---------- SRT helpers ----------

function pad(n, width = 2) {
  return String(n).padStart(width, '0');
}
function srtTime(ms) {
  const h = Math.floor(ms / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  const s = Math.floor((ms % 60000) / 1000);
  const msPart = ms % 1000;
  return `${pad(h)}:${pad(m)}:${pad(s)},${pad(msPart, 3)}`;
}
function buildSrt(entries) {
  let out = '';
  let idx = 1;
  for (const e of entries) {
    if (!e.text || e.endMs <= e.startMs) continue;
    out += `${idx}\n`;
    out += `${srtTime(e.startMs)} --> ${srtTime(e.endMs)}\n`;
    out += `${e.text}\n\n`;
    idx++;
  }
  return out;
}

// ---------- Playwright helpers ----------

async function dismissUpdateDialog(page) {
  try {
    await page.keyboard.press('Escape');
    await sleep(400);
  } catch (e) { /* ignora */ }
}

async function typeTerminal(page, text) {
  const termFrame = page.frame({ name: 'term' });
  let focused = false;
  if (termFrame) {
    try {
      const ta = termFrame.locator('.xterm-helper-textarea');
      if ((await ta.count()) > 0) {
        await ta.click({ force: true });
        focused = true;
      }
    } catch (e) { /* ignora */ }
  }
  if (!focused) {
    await page.mouse.click(WIDTH / 2, HEIGHT / 2);
  }
  await sleep(100);
  await page.keyboard.type(text, { delay: 8 });
}

async function pressEnter(page) {
  await page.keyboard.press('Enter');
  await sleep(600);
}

// ---------- Leitura do terminal via xterm (window.term exposto pelo ttyd) ----------

async function readTerminal(page) {
  const termFrame = page.frame({ name: 'term' });
  if (!termFrame) return { ok: false, text: '', lines: [] };
  return termFrame.evaluate(() => {
    const t = window.term;
    if (!t || !t.buffer) return { ok: false, text: '', lines: [] };
    const buf = t.buffer.active;
    const lines = [];
    for (let i = 0; i < buf.length; i++) {
      const line = buf.getLine(i);
      lines.push(line ? line.translateToString(true) : '');
    }
    return { ok: true, len: buf.length, text: lines.join('\n'), lines };
  });
}

function collapseWs(s) {
  return String(s).replace(/\s+/g, '');
}

const GUID_RE = /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/i;

function extractInvocationId(text) {
  const s = collapseWs(text);
  const all = [...s.matchAll(new RegExp(GUID_RE.source, 'gi'))];
  return all.length ? all[all.length - 1][0] : null;
}

// Extrai um GUID pelo rotulo ("Invocation ID: <guid>"). O TUI do opencode
// mostra o Invocation ID ANTES do Approval ID, entao pegar "o ultimo GUID"
// devolve o ID errado — sempre extrair por rotulo. O terminal estreito pode
// QUEBRAR o GUID em duas linhas, entao o texto tambem e lido "achatado"
// (sem quebras de linha) antes de desistir.
function extractLabeledGuid(text, label) {
  const re = new RegExp(label + '[^0-9A-F]{0,40}(' + GUID_RE.source + ')', 'gi');
  const raw = String(text);
  let all = [...raw.matchAll(re)];
  if (all.length) return all[all.length - 1][1];
  const flat = raw.replace(/\n+/g, '');
  all = [...flat.matchAll(re)];
  return all.length ? all[all.length - 1][1] : null;
}

// Espera o agente terminar (buffer do xterm fica quieto) antes de trocar de view.
async function waitTerminalIdle(page, opts = {}) {
  const minMs = opts.minMs ?? 8000;
  const quietMs = opts.quietMs ?? 3000;
  const maxMs = opts.maxMs ?? 120000;
  const start = Date.now();
  let prev = await readTerminal(page);
  let stableSince = null;
  while (Date.now() - start < maxMs) {
    await new Promise((r) => setTimeout(r, 1000));
    const cur = await readTerminal(page);
    if (!cur.ok) continue;
    if (cur.text !== prev.text) {
      prev = cur;
      stableSince = null;
    } else if (Date.now() - start >= minMs && Date.now() - (stableSince || start) >= quietMs) {
      return { stopped: true, text: cur.text, elapsed: Date.now() - start };
    } else if (stableSince === null) {
      stableSince = start;
    }
  }
  const cur = await readTerminal(page);
  return { stopped: false, text: cur ? cur.text : '', elapsed: Date.now() - start };
}

async function nudgeFrame(page, name) {
  const frame = page.frame({ name });
  if (!frame) return;
  try {
    if (name === 'term') {
      await frame.evaluate(() => {
        const t = window.term;
        if (!t) return;
        try { if (t.fit) t.fit(); } catch (e) {}
        try { if (t.refresh) t.refresh(0, t.rows - 1); } catch (e) {}
      });
    } else {
      await frame.evaluate(() => {
        try { window.dispatchEvent(new Event('resize')); } catch (e) {}
      });
    }
  } catch (e) { /* frame pode estar navegando */ }
}

async function showView(page, view) {
  await page.evaluate((v) => window.__stage.show(v), view);
  await sleep(200);
  if (view === 'terminal') await nudgeFrame(page, 'term');
  if (view === 'portal') await nudgeFrame(page, 'portal');
}

async function loadPortal(page, url) {
  const frame = page.frame({ name: 'portal' });
  // Acrescenta um cache-buster para forcar o carregamento de conteudo novo
  // do servidor sempre que a tela do IRIS eh (re)entrada (novas mensagens,
  // novas tarefas de aprovacao, etc.).
  const fresh = url + (url.includes('?') ? '&' : '?') + '_=' + Date.now();

  // Aguarda o commit da navegacao (framenavigated) e o load do novo documento.
  const nav = frame
    ? page.waitForEvent('framenavigated', { predicate: (f) => f === frame, timeout: 30000 }).catch(() => null)
    : Promise.resolve(null);
  await page.evaluate((u) => window.__stage.loadPortal(u), fresh);
  await nav;
  try {
    if (frame) await frame.waitForLoadState('load', { timeout: 30000 });
  } catch (e) { /* pode demorar */ }

  // Espera o SPA popular o body (a pagina anterior ja foi substituida no commit).
  const deadline = Date.now() + 25000;
  let finalUrl = '';
  let finalLen = 0;
  while (Date.now() < deadline) {
    const f = page.frame({ name: 'portal' });
    if (f) {
      try { finalUrl = f.url(); } catch (e) { /* ignora */ }
      try {
        const len = await f.evaluate(() => {
          try {
            if (!document.body) return 0;
            return (document.body.innerText || '').trim().length;
          } catch (e) { return 0; }
        });
        if (len > finalLen) finalLen = len;
        if (len > 40) break;
      } catch (e) { /* ignora */ }
    }
    await sleep(300);
  }
  log(`Portal OK: ${url} -> ${finalUrl} (texto=${finalLen})`);
  await sleep(400);
  await nudgeFrame(page, 'portal');
}

// ---------- IRIS User Portal (Workflow) — interacao real no iframe ----------

// O ZEN abre um confirm() antes de executar a acao do botao; sem handler o
// Playwright dispensa o dialogo e a acao nunca acontece.
function installDialogHandler(page) {
  page.on('dialog', (d) => d.accept().catch(() => {}));
}

function portalFrame(page) {
  return page.frame({ name: 'portal' });
}

// Seleciona a task na inbox pelo ApprovalId (o Subject da task e
// "Approval: <ApprovalId>") e espera o painel de detalhes carregar.
async function selectPortalTask(page, approvalId) {
  const frame = portalFrame(page);
  if (!frame) throw new Error('iframe do portal nao encontrado');
  const row = frame.locator('#folderList tr', { hasText: approvalId }).first();
  await row.waitFor({ state: 'visible', timeout: 60000 });
  await row.click();
  await frame.waitForLoadState('load', { timeout: 30000 }).catch(() => {});
  await frame
    .locator('input[name="BTN_$Accept"], input[name="BTN_Approve"], input[name="BTN_Reject"]')
    .first()
    .waitFor({ state: 'visible', timeout: 45000 })
    .catch(() => {});
  await sleep(1500);
  log('Task selecionada no User Portal:', approvalId);
}

// Clica em um botao de acao do painel de detalhes:
// BTN_$Accept (assumir posse), BTN_Approve, BTN_Reject.
async function clickPortalAction(page, actionName) {
  const frame = portalFrame(page);
  if (!frame) throw new Error('iframe do portal nao encontrado');
  const btn = frame.locator(`input[name="BTN_${actionName}"]`).first();
  await btn.waitFor({ state: 'visible', timeout: 45000 });
  await btn.click();
  // O ZEN faz submit do form e navega dentro do iframe.
  await sleep(2500);
  await frame.waitForLoadState('load', { timeout: 45000 }).catch(() => {});
  await sleep(1800);
  log('Acao no User Portal:', actionName);
}

// Espera a task sumir da inbox (decisao concluida).
async function waitPortalTaskGone(page, approvalId) {
  const frame = portalFrame(page);
  if (!frame) return;
  await frame
    .waitForFunction((id) => !(document.body.innerText || '').includes(id), approvalId, {
      timeout: 60000,
    })
    .catch(() => {});
  await sleep(1200);
}

async function setCaption(page, ctx, text) {
  const now = Date.now() - ctx.t0;
  // fecha a legenda anterior
  if (ctx.curCaption) {
    ctx.entries.push({ startMs: ctx.curStart, endMs: now, text: ctx.curCaption });
    ctx.curCaption = null;
  }
  ctx.curCaption = text;
  ctx.curStart = now;
  await page.evaluate((t) => window.__caption(t), text);
  log('Legenda:', text);
}

// ---------- Consultas ao IRIS (via docker exec) + decisao no User Portal ----------
//
// ATENCAO: o "iris session" executa linha a linha e NAO aceita blocos { }.
// Todo script abaixo usa apenas comandos de uma linha (sem While/For/If com
// bloco). Lacos ficam do lado do JavaScript.

// Aprovacao pendente mais recente (a fila do video tem uma por vez).
// Retorna "<ApprovalId>|<InvocationId>".
const FIND_PENDING_SCRIPT = `
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("SELECT TOP 1 ApprovalId, InvocationId FROM br_musketeers_InteropMCP.Approvals WHERE Decision = 'pending' ORDER BY ID DESC")
Set rs = stmt.%Execute()
Set o = ""
If rs.%Next() Set o = rs.%Get("ApprovalId") _ "|" _ rs.%Get("InvocationId")
Write o, !
Halt
`;

// Aprovacao pendente mais antiga (usada na limpeza, uma por vez).
const FIND_OLDEST_PENDING_SCRIPT = `
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("SELECT TOP 1 ApprovalId FROM br_musketeers_InteropMCP.Approvals WHERE Decision = 'pending' ORDER BY ID ASC")
Set rs = stmt.%Execute()
Set found = ""
If rs.%Next() Set found = rs.%Get("ApprovalId")
Write found, !
Halt
`;

// Rejeita uma aprovacao pendente (usado so na limpeza).
const REJECT_SCRIPT = (id) => `
Do ##class(br.musketeers.InteropMCP.Approvals).Reject("${id}", "video-cleanup", "Stale approval rejected by record-video.mjs cleanup.")
Write "rejected", !
Halt
`;

// Remove da inbox do Workflow as tasks que ficaram em aberto.
const CLEAR_WORKLIST_SCRIPT = `
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("DELETE FROM EnsLib_Workflow.Worklist WHERE Task IN (SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE TaskStatus_IsComplete = 0)")
Set removed = stmt.%Execute()
Write "worklist_removed=", removed, !
Halt
`;

const GUID_LINE = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i;
const INVOCATION_STATUSES = [
  'pending-approval',
  'executing',
  'completed',
  'failed',
  'rejected',
  'received',
];

function irisSession(script) {
  try {
    return execFileSync(
      'docker',
      ['exec', '-i', CONTAINER, 'iris', 'session', 'iris', '-U', 'IRISAPP'],
      { input: script, encoding: 'utf8', timeout: 90000 }
    );
  } catch (e) {
    return e.stdout ? e.stdout.toString() : String(e);
  }
}

// Aprovacao pendente casada pela InvocationId (evita pegar aprovacao antiga).
const FIND_APPROVAL_SCRIPT = (invId) => `
Set invId = "${invId}"
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("SELECT ApprovalId FROM br_musketeers_InteropMCP.Approvals WHERE InvocationId = ? AND Decision = 'pending'")
Set rs = stmt.%Execute(invId)
Set found = ""
If rs.%Next() Set found = rs.%Get("ApprovalId")
Write found, !
Halt
`;

const STATUS_SCRIPT = (invId) => `
Set invId = "${invId}"
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("SELECT Status FROM br_musketeers_InteropMCP.Invocations WHERE InvocationId = ?")
Set rs = stmt.%Execute(invId)
Set st = ""
If rs.%Next() Set st = rs.%Get("Status")
Write st, !
Halt
`;

// No output do "iris session" a linha echoed do comando tambem contem o GUID:
// so aceita uma linha que seja exatamente o GUID.
function parseGuidLine(out) {
  for (const l of String(out).split('\n').map((x) => x.trim())) {
    if (GUID_LINE.test(l)) return l;
  }
  return '';
}

function parseStatusLine(out) {
  for (const l of String(out).split('\n').map((x) => x.trim())) {
    if (INVOCATION_STATUSES.includes(l)) return l;
  }
  return '';
}

// Espera a aprovacao pendente da invocacao aparecer no IRIS.
async function findPendingApprovalId(invocationId) {
  for (let i = 0; i < 30; i++) {
    const id = parseGuidLine(irisSession(FIND_APPROVAL_SCRIPT(invocationId)));
    if (id) return id;
    await sleep(2000);
  }
  return '';
}

// Aprovacao pendente mais recente no IRIS: <ApprovalId>|<InvocationId>.
// Fonte AUTORITATIVA do invocationId — o texto do TUI pode ter o GUID
// quebrado de linha, o que quebra a extracao por rotulo.
function findLatestPendingApproval() {
  const out = irisSession(FIND_PENDING_SCRIPT);
  const m = String(out).match(
    /([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})\|([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})/i
  );
  return m ? { approvalId: m[1], invocationId: m[2] } : null;
}

// Limpa o estado de uma execucao anterior: rejeita as aprovacoes pendentes
// (uma por vez, sem blocos no "iris session") e esvazia a inbox do Workflow.
function cleanupState() {
  let rejected = 0;
  for (let i = 0; i < 20; i++) {
    const id = parseGuidLine(irisSession(FIND_OLDEST_PENDING_SCRIPT));
    if (!id) break;
    irisSession(REJECT_SCRIPT(id));
    rejected++;
  }
  const wl = irisSession(CLEAR_WORKLIST_SCRIPT);
  const m = String(wl).match(/worklist_removed=\d+/i);
  return `rejected=${rejected} ${m ? m[0] : '(worklist: sem marcador)'}`;
}

// Aplica a decisao no IRIS User Portal (Accept + Approve/Reject) e espera a
// invocacao sair de "pending-approval".
async function decideInPortal(page, invocationId, decision, knownApprovalId) {
  if (!invocationId) {
    log('Decisao no portal: invocationId ausente — pulando.');
    return '';
  }
  const approvalId = knownApprovalId || (await findPendingApprovalId(invocationId));
  if (!approvalId) {
    log('Nenhuma aprovacao pendente encontrada para', invocationId);
    return '';
  }
  log('Aprovacao pendente:', approvalId, '-> decisao:', decision);

  // Recarrega o portal para a task aparecer na inbox (cache-buster).
  await loadPortal(page, WORKFLOW_URL);
  await selectPortalTask(page, approvalId);
  await clickPortalAction(page, '$Accept');
  await clickPortalAction(page, decision);
  await waitPortalTaskGone(page, approvalId);

  // Confirma a transicao de status antes de seguir para o status tool.
  let status = '';
  for (let i = 0; i < 30; i++) {
    status = parseStatusLine(irisSession(STATUS_SCRIPT(invocationId)));
    if (status === 'completed' || status === 'failed' || status === 'rejected') break;
    await sleep(1500);
  }
  log('Status da invocacao apos a decisao:', status || '(desconhecido)');
  return status;
}

// ---------- Steps do tutorial (en-US) ----------

const STEPS = [
  { view: 'terminal', caption: 'InteropMCP — Turn your IRIS Interoperability Productions into MCP tools for AI agents.', waitMs: 3000 },
  { view: 'terminal', caption: 'The demo production is only an example — InteropMCP publishes any IRIS Interoperability Production.', waitMs: 3000 },
  {
    view: 'terminal',
    action: 'type',
    text: 'Use the PayLookup tool with OrderId 88201 and CustomerId C-1',
    caption: 'Call the readonly PayLookup tool.',
    waitMs: 25000,
  },
  { view: 'portal', portal: MESSAGE_VIEWER_URL, caption: 'In the IRIS Message Viewer, every call flows through the same BS → BP → BO production as before.', waitMs: 10000 },
  {
    view: 'terminal',
    action: 'type',
    text: 'Use the CustomerUpdate tool with CustomerId 1 and NewAddress "Av. Paulista, 1000 - Sao Paulo/SP"',
    caption: 'Call the write CustomerUpdate tool. The guardrail logs the decision.',
    waitMs: 25000,
  },
  { view: 'portal', portal: MESSAGE_VIEWER_URL, caption: 'The message is processed by the existing production.', waitMs: 9000 },
  {
    view: 'terminal',
    action: 'type',
    text: 'Use the AccountBlock tool with CustomerId 1, BlockType "permanent", and Reason "Restricted CNPJ detected"',
    caption: 'Call the critical AccountBlock tool. It is held for human approval.',
    captureGuid: 'invocationId',
    waitMs: 25000,
  },
  {
    view: 'terminal',
    action: 'type',
    text: 'Use the GetInvocationStatus tool with invocationId ${invocationId}',
    caption: 'GetInvocationStatus shows pending-approval — nothing reached the production yet.',
    waitMs: 25000,
  },
  { view: 'portal', portal: WORKFLOW_URL, caption: 'The approval is a native IRIS Workflow task in the User Portal inbox.', waitMs: 10000 },
  {
    view: 'portal',
    action: 'portalDecision',
    decision: 'Reject',
    invocation: 'invocationId',
    approval: 'approvalId',
    caption: 'The operator takes ownership (Accept) and rejects it in the IRIS User Portal.',
    waitMs: 20000,
  },
  {
    view: 'terminal',
    action: 'type',
    text: 'Use the GetInvocationStatus tool with invocationId ${invocationId}',
    caption: 'The invocation is rejected — the AccountBlock Business Service never ran.',
    waitMs: 25000,
  },
  {
    view: 'terminal',
    action: 'type',
    text: 'Check the risk for Cnpj 99.999.999/0001-90 with full scope',
    caption: 'For a non-restricted CNPJ, the agent calls RiskCheck directly.',
    waitMs: 25000,
  },
  { view: 'portal', portal: MESSAGE_VIEWER_URL, caption: 'The RiskCheck request appears in the production.', waitMs: 8000 },
  {
    view: 'terminal',
    action: 'type',
    text: 'Check the risk for Cnpj 12.345.678/0001-90 with full scope',
    caption: 'For a restricted CNPJ, the agent creates a Workflow task instead of calling RiskCheck.',
    captureGuid: 'riskInvocationId',
    waitMs: 25000,
  },
  { view: 'portal', portal: WORKFLOW_URL, caption: 'A new approval task is created — humans retain final authority.', waitMs: 10000 },
  {
    view: 'portal',
    action: 'portalDecision',
    decision: 'Approve',
    invocation: 'riskInvocationId',
    approval: 'riskApprovalId',
    caption: 'The operator approves it in the IRIS User Portal — the Business Service runs.',
    waitMs: 20000,
  },
  { view: 'portal', portal: MESSAGE_VIEWER_URL, caption: 'The RiskCheck message is processed by the production.', waitMs: 9000 },
  {
    view: 'terminal',
    action: 'type',
    text: 'Use the GetInvocationStatus tool with invocationId ${riskInvocationId}',
    caption: 'After approval, the invocation is completed.',
    waitMs: 25000,
  },
  { view: 'terminal', caption: 'InteropMCP lets AI agents talk to any IRIS Interoperability Production without rewriting it.', waitMs: 6000 },
];

// ---------- Login do portal (contexto nao gravado) ----------

async function loginForCookies(browser) {
  // locale en-US: o portal IRIS renderiza em ingles (mesmo das acoes Approve/Reject).
  const loginCtx = await browser.newContext({ colorScheme: 'dark', locale: 'en-US' });
  const lp = await loginCtx.newPage();
  await lp.goto(PORTAL_LOGIN_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(1500);
  if ((await lp.locator('input[name="IRISPassword"]').count()) > 0) {
    await lp.locator('input[name="IRISUsername"]').fill(USER);
    await lp.locator('input[name="IRISPassword"]').fill(PASS);
    await lp.locator('input[name="IRISLogin"]').click();
    await sleep(2000);
  }
  const cookies = await loginCtx.cookies(PORTAL_BASE);
  log('Cookies obtidas para o portal:', cookies.length);
  await loginCtx.close();
  return cookies;
}

// ---------- Main ----------

async function main() {
  ensureDir(OUTPUT_DIR);
  log('=== Iniciando gravacao do tutorial InteropMCP (headless) ===');
  log('Tela:', WIDTH, 'x', HEIGHT);

  // Estado limpo: a inbox do User Portal aparece no video.
  log('Limpando estado anterior:', cleanupState());

  const server = await startStaticServer();

  const browser = await chromium.launch({
    headless: true,
    slowMo: 80,
    // Dark mode real: o portal IRIS eh claro e nao responde a prefers-color-scheme,
    // entao habilitamos o auto-dark do Chromium para escurecer o conteudo.
    args: [
      '--force-dark-mode',
      '--enable-features=WebContentsForceDark',
      '--blink-settings=forceDarkModeEnabled=true',
    ],
  });

  // Autentica o portal num contexto separado (nao gravado).
  const cookies = await loginForCookies(browser);

  // Contexto de gravacao (dark mode via prefers-color-scheme).
  const context = await browser.newContext({
    colorScheme: 'dark',
    viewport: { width: WIDTH, height: HEIGHT },
    recordVideo: { dir: OUTPUT_DIR, size: { width: WIDTH, height: HEIGHT } },
    locale: 'en-US',
  });
  await context.addCookies(cookies);

  const page = await context.newPage();
  // O ZEN abre um confirm() antes de executar a acao (Accept/Approve/Reject).
  installDialogHandler(page);
  const video = page.video();
  const t0 = Date.now();

  await page.goto(STAGE_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
  // Aguarda o terminal (opencode TUI) ficar pronto.
  await sleep(8000);
  await dismissUpdateDialog(page);

  const ctx = { t0, entries: [], curCaption: null, curStart: 0 };

  log('--- Iniciando timeline do tutorial ---');
  for (const step of STEPS) {
    const startMs = Date.now() - t0;

    if (step.view) {
      await showView(page, step.view);
    }
    if (step.portal) {
      await loadPortal(page, step.portal);
    }

    if (step.caption) {
      await setCaption(page, ctx, step.caption);
    }

    if (step.action === 'type') {
      let text = step.text;
      if (text.includes('${invocationId}') && ctx.invocationId) {
        text = text.replace(/\$\{invocationId\}/g, ctx.invocationId);
      }
      if (text.includes('${riskInvocationId}') && ctx.riskInvocationId) {
        text = text.replace(/\$\{riskInvocationId\}/g, ctx.riskInvocationId);
      }
      await typeTerminal(page, text);
      await pressEnter(page);
      await waitTerminalIdle(page);
      if (step.captureGuid) {
        // Fonte AUTORITATIVA: o IRIS. O texto do TUI pode ter o GUID quebrado
        // de linha (terminal estreito), o que faz a extracao por rotulo falhar
        // e cair no "ultimo GUID" — que e o ApprovalId, nao o InvocationId.
        let found = null;
        for (let i = 0; i < 15 && !found; i++) {
          found = findLatestPendingApproval();
          if (!found) await sleep(2000);
        }
        if (!found) throw new Error('aprovacao pendente nao encontrada no IRIS');
        const cur = await readTerminal(page);
        const tuiId = extractLabeledGuid(cur.ok ? cur.text : '', 'Invocation ID');
        if (tuiId && tuiId !== found.invocationId) {
          log('AVISO: invocationId do TUI difere do IRIS; usando o do IRIS:', tuiId);
        }
        ctx[step.captureGuid] = found.invocationId;
        ctx[step.captureGuid === 'invocationId' ? 'approvalId' : 'riskApprovalId'] = found.approvalId;
        log(
          `${step.captureGuid} (IRIS):`, found.invocationId,
          '| approvalId:', found.approvalId
        );
      }
    } else if (step.action === 'enter') {
      await pressEnter(page);
    } else if (step.action === 'portalDecision') {
      await decideInPortal(
        page,
        ctx[step.invocation],
        step.decision,
        ctx[step.approval]
      );
    } else if (step.action === 'wait') {
      await page.waitForTimeout(step.waitMs || 0);
    } else {
      // só troca de view/legenda: aguarda para o espectador ver
      await page.waitForTimeout(Math.min(step.waitMs || 4000, 12000));
    }
  }

  // Fecha a ultima legenda.
  const endMs = Date.now() - t0;
  if (ctx.curCaption) {
    ctx.entries.push({ startMs: ctx.curStart, endMs: Math.max(endMs, ctx.curStart + 1000), text: ctx.curCaption });
  }

  log('--- Finalizando gravacao ---');
  await context.close();
  await browser.close();
  server.close();

  const webmPath = await video.path();
  log('WebM gravado:', webmPath);

  const rawMp4 = join(OUTPUT_DIR, 'tutorial-raw.mp4');
  ffmpeg([
    '-y', '-i', webmPath,
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '22', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
    rawMp4,
  ]);
  log('MP4 gerado:', rawMp4);

  const srtPath = join(OUTPUT_DIR, 'subtitles.srt');
  writeFileSync(srtPath, buildSrt(ctx.entries), 'utf8');
  log('SRT gerado:', srtPath, '(' + ctx.entries.length + ' entradas)');

  // Remove o WebM temporario (ja convertido).
  try { unlinkSync(webmPath); } catch (e) { /* ignora */ }

  return { rawMp4, srtPath };
}

main().catch((err) => {
  console.error('ERRO:', err);
  process.exit(1);
});
