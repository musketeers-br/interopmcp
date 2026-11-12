#!/usr/bin/env node
/**
 * record-screenshots.mjs — Captura as telas do tutorial InteropMCP (en-US) como PNG.
 *
 * Mesmos mecanismos de record-video.mjs, com video no lugar de imagem:
 *   - Um unico contexto Playwright Chromium headless (1324x736).
 *   - Login do portal IRIS feito em um contexto separado (nao gravado) e os
 *     cookies copiados para o contexto de captura (evita "flash" de login).
 *   - Terminal web (ttyd -> Opencode CLI) em http://localhost:7681 para digitar
 *     os prompts e ler o buffer do xterm (window.term) para detectar o fim da
 *     resposta do agente.
 *   - Consultas reais no IRIS via "docker exec ... iris session" para casar a
 *     aprovacao pela InvocationId e ler o status da invocacao.
 *   - Cache-buster na navegacao do portal para sempre ver conteudo novo.
 *
 * Diferenca: em vez de gravar video, cada passo produz um PNG em
 * docs/articles/img/ com o padrao article-<n>-step-<nn>-<slug>.png.
 *
 * Uso: node record-screenshots.mjs [--no-clean] [--keep-open]
 */

import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { existsSync, mkdirSync } from 'fs';
import { execFileSync } from 'child_process';
import { chromium } from 'playwright';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const REPO_DIR = join(__dirname, '..', '..');
const OUT_DIR = join(REPO_DIR, 'docs', 'articles', 'img');
const ARTICLE = 'article-1';

const WIDTH = 1324;
const HEIGHT = 736;

// URLs
const TTYD_URL = 'http://localhost:7681/';
const PORTAL_BASE = 'http://localhost:52773';
const PORTAL_LOGIN_URL = `${PORTAL_BASE}/csp/irisapp/EnsPortal.MessageViewer.zen`;
const WORKFLOW_URL = `${PORTAL_BASE}/csp/irisapp/_DeepSee.UserPortal.Workflow.zen?$NAMESPACE=IRISAPP`;
const MESSAGE_VIEWER_URL = `${PORTAL_BASE}/ui/interop/message-viewer/index.html?%24NAMESPACE=IRISAPP`;

const USER = '_SYSTEM';
const PASS = 'SYS';
const CONTAINER = 'ai-hub-demo-web-iris-1';

// Prompts do agente (mesmos do artigo)
const PROMPT_ACCOUNT_BLOCK =
  'Use the AccountBlock tool with CustomerId 1, BlockType "permanent", and Reason "Restricted CNPJ detected"';
const PROMPT_RISK_RESTRICTED = 'Check the risk for Cnpj 12.345.678/0001-90 with full scope';

const ARGS = process.argv.slice(2);
const DO_CLEAN = !ARGS.includes('--no-clean');
const KEEP_OPEN = ARGS.includes('--keep-open');

// ---------- util ----------

function log(...args) {
  const ts = new Date().toISOString().replace('T', ' ').substring(0, 19);
  console.log(`[${ts}]`, ...args);
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function ensureDir(p) {
  if (!existsSync(p)) mkdirSync(p, { recursive: true });
}

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

const GUID_RE = /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/i;
const GUID_LINE_RE = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i;
const INVOCATION_STATUSES = [
  'pending-approval',
  'executing',
  'completed',
  'failed',
  'rejected',
  'received',
];

// Extrai um GUID pelo rotulo ("Invocation ID: <guid>"). O TUI mostra o
// Invocation ID antes do Approval ID, entao pegar "o ultimo GUID" nao serve.
// O buffer do xterm acumula as mensagens, entao vale a ULTIMA ocorrencia
// (a mais recente). O terminal estreito pode QUEBRAR o GUID em duas linhas,
// entao o texto tambem e lido "achatado" (sem quebras de linha).
function extractLabeledGuid(text, label) {
  const re = new RegExp(label + '[^0-9A-F]{0,40}(' + GUID_RE.source + ')', 'gi');
  const raw = String(text);
  let all = [...raw.matchAll(re)];
  if (all.length) return all[all.length - 1][1];
  const flat = raw.replace(/\n+/g, '');
  all = [...flat.matchAll(re)];
  return all.length ? all[all.length - 1][1] : null;
}

// Aprovacao pendente mais recente no IRIS: <ApprovalId>|<InvocationId>.
function findLatestPendingApproval() {
  const out = irisSession(FIND_PENDING_SCRIPT);
  const m = String(out).match(
    /([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})\|([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})/i
  );
  return m ? { approvalId: m[1], invocationId: m[2] } : null;
}

// Limpa o estado de uma execucao anterior (sem blocos no "iris session").
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

// No output do "iris session" a linha echoed do comando tambem contem o GUID:
// so aceita uma linha que seja exatamente o GUID.
function parseGuidLine(out) {
  for (const l of String(out).split('\n').map((x) => x.trim())) {
    if (GUID_LINE_RE.test(l)) return l;
  }
  return '';
}

function parseStatusLine(out) {
  for (const l of String(out).split('\n').map((x) => x.trim())) {
    if (INVOCATION_STATUSES.includes(l)) return l;
  }
  return '';
}

// ---------- IRIS helpers (via docker exec) ----------

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

// Aprovacao pendente mais recente (fonte autoritativa do invocationId).
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

// Aprovacao pendente mais antiga (limpeza, uma por vez).
const FIND_OLDEST_PENDING_SCRIPT = `
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("SELECT TOP 1 ApprovalId FROM br_musketeers_InteropMCP.Approvals WHERE Decision = 'pending' ORDER BY ID ASC")
Set rs = stmt.%Execute()
Set found = ""
If rs.%Next() Set found = rs.%Get("ApprovalId")
Write found, !
Halt
`;

// Rejeita uma aprovacao pendente (limpeza).
const REJECT_SCRIPT = (id) => `
Do ##class(br.musketeers.InteropMCP.Approvals).Reject("${id}", "screenshot-cleanup", "Stale approval rejected by record-screenshots.mjs cleanup.")
Write "rejected", !
Halt
`;

// Remove da inbox as tasks em aberto.
const CLEAR_WORKLIST_SCRIPT = `
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("DELETE FROM EnsLib_Workflow.Worklist WHERE Task IN (SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE TaskStatus_IsComplete = 0)")
Set removed = stmt.%Execute()
Write "worklist_removed=", removed, !
Halt
`;

// ---------- Portal (User Portal) ----------

async function loginForCookies(browser) {
  const loginCtx = await browser.newContext({ colorScheme: 'dark', locale: 'en-US' });
  const lp = await loginCtx.newPage();
  await lp.goto(PORTAL_LOGIN_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(1500);
  if ((await lp.locator('input[name="IRISPassword"]').count()) > 0) {
    await lp.locator('input[name="IRISUsername"]').fill(USER);
    await lp.locator('input[name="IRISPassword"]').fill(PASS);
    await lp.locator('input[name="IRISLogin"]').click();
    await sleep(2500);
  }
  const cookies = await loginCtx.cookies(PORTAL_BASE);
  log('Cookies do portal obtained:', cookies.length);
  await loginCtx.close();
  return cookies;
}

async function openPortalPage(context) {
  const page = await context.newPage();
  // O ZEN abre um confirm() antes de executar a acao do botao.
  page.on('dialog', (d) => d.accept().catch(() => {}));
  await gotoWorkflow(page);
  return page;
}

async function gotoWorkflow(page) {
  const fresh = WORKFLOW_URL + (WORKFLOW_URL.includes('?') ? '&' : '?') + '_=' + Date.now();
  await page.goto(fresh, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForLoadState('load', { timeout: 30000 }).catch(() => {});
  await page
    .waitForFunction(() => document.body && document.body.innerText.trim().length > 40, null, {
      timeout: 30000,
    })
    .catch(() => {});
  await sleep(1500);
}

// Seleciona a task pelo ApprovalId (o Subject da task e "Approval: <ApprovalId>")
// e espera o painel de detalhes carregar.
async function selectTask(page, approvalId) {
  const row = page.locator('#folderList tr', { hasText: approvalId }).first();
  await row.waitFor({ state: 'visible', timeout: 45000 });
  await Promise.all([
    page.waitForURL(/ID=/, { timeout: 45000 }).catch(() => {}),
    row.click(),
  ]);
  await page.waitForLoadState('load', { timeout: 30000 }).catch(() => {});
  await page
    .waitForSelector('input[name="BTN_$Accept"], input[name="BTN_Approve"], input[name="BTN_Reject"]', {
      timeout: 45000,
    })
    .catch(() => {});
  await sleep(1200);
}

// Clica em um botao de acao do painel de detalhes (BTN_$Accept, BTN_Approve, BTN_Reject).
async function clickActionButton(page, actionName) {
  const btn = page.locator(`input[name="BTN_${actionName}"]`);
  await btn.waitFor({ state: 'visible', timeout: 45000 });
  await btn.click();
  await page.waitForLoadState('load', { timeout: 45000 }).catch(() => {});
  await sleep(1500);
}

// Espera a task sumir da inbox (acao concluida).
async function waitTaskGone(page, approvalId) {
  await page
    .waitForFunction((id) => !(document.body.innerText || '').includes(id), approvalId, { timeout: 45000 })
    .catch(() => {});
  await sleep(800);
}

async function openMessageViewer(context) {
  const page = await context.newPage();
  await page.goto(MESSAGE_VIEWER_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForLoadState('load', { timeout: 30000 }).catch(() => {});
  const deadline = Date.now() + 25000;
  let len = 0;
  while (Date.now() < deadline) {
    len = await page
      .evaluate(() => {
        try {
          return document.body ? (document.body.innerText || '').trim().length : 0;
        } catch (e) {
          return 0;
        }
      })
      .catch(() => 0);
    if (len > 40) break;
    await sleep(500);
  }
  await sleep(6000);
  log('Message Viewer pronto (texto=' + len + ')');
  return page;
}

// ---------- Terminal (opencode via ttyd) ----------

async function openTerminalPage(context) {
  const page = await context.newPage();
  await page.goto(TTYD_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(9000);
  try {
    await page.keyboard.press('Escape');
    await sleep(400);
  } catch (e) {
    /* ignora */
  }
  return page;
}

async function readTerminal(page) {
  return page
    .evaluate(() => {
      const t = window.term;
      if (!t || !t.buffer) return { ok: false, text: '' };
      const buf = t.buffer.active;
      const lines = [];
      for (let i = 0; i < buf.length; i++) {
        const line = buf.getLine(i);
        lines.push(line ? line.translateToString(true) : '');
      }
      return { ok: true, text: lines.join('\n') };
    })
    .catch(() => ({ ok: false, text: '' }));
}

// Espera o agente terminar: o buffer do xterm fica quieto.
async function waitTerminalIdle(page, opts = {}) {
  const minMs = opts.minMs ?? 8000;
  const quietMs = opts.quietMs ?? 3000;
  const maxMs = opts.maxMs ?? 180000;
  const start = Date.now();
  let prev = await readTerminal(page);
  let stableSince = null;
  while (Date.now() - start < maxMs) {
    await sleep(1000);
    const cur = await readTerminal(page);
    if (!cur.ok) continue;
    if (cur.text !== prev.text) {
      prev = cur;
      stableSince = null;
    } else if (Date.now() - start >= minMs && Date.now() - (stableSince || start) >= quietMs) {
      return { stopped: true, elapsed: Date.now() - start };
    } else if (stableSince === null) {
      stableSince = start;
    }
  }
  return { stopped: false, elapsed: Date.now() - start };
}

async function typeTerminal(page, text) {
  const ta = page.locator('.xterm-helper-textarea');
  if ((await ta.count()) > 0) {
    await ta.click({ force: true });
  } else {
    await page.mouse.click(WIDTH / 2, HEIGHT / 2);
  }
  await sleep(150);
  await page.keyboard.type(text, { delay: 8 });
  await page.keyboard.press('Enter');
}

// ---------- Captura ----------

let shotCount = 0;
async function shot(page, slug) {
  const file = join(OUT_DIR, `${ARTICLE}-${slug}.png`);
  await page.screenshot({ path: file });
  shotCount++;
  log('Screenshot:', file);
  return file;
}

// ---------- Main ----------

async function main() {
  ensureDir(OUT_DIR);

  if (DO_CLEAN) {
    log('Cleanup:', cleanupState());
  }

  const browser = await chromium.launch({
    headless: true,
    slowMo: 60,
    args: [
      '--force-dark-mode',
      '--enable-features=WebContentsForceDark',
      '--blink-settings=forceDarkModeEnabled=true',
    ],
  });

  const cookies = await loginForCookies(browser);

  const context = await browser.newContext({
    colorScheme: 'dark',
    viewport: { width: WIDTH, height: HEIGHT },
    locale: 'en-US',
  });
  await context.addCookies(cookies);

  const term = await openTerminalPage(context);
  const portal = await openPortalPage(context);

  // ---- Step 5: AccountBlock (critical) fica em held ----
  log('--- Step 5: AccountBlock ---');
  await typeTerminal(term, PROMPT_ACCOUNT_BLOCK);
  await waitTerminalIdle(term);
  const termText = (await readTerminal(term)).text;
  // Fonte AUTORITATIVA: o IRIS. O texto do TUI pode ter o GUID quebrado de
  // linha, o que faz a extracao por rotulo falhar.
  const pending = findLatestPendingApproval();
  if (!pending) throw new Error('aprovacao pendente nao encontrada no IRIS');
  const invocationId = pending.invocationId;
  const approvalId = pending.approvalId;
  const tuiInvocationId = extractLabeledGuid(termText, 'Invocation ID');
  if (tuiInvocationId && tuiInvocationId !== invocationId) {
    log('AVISO: invocationId do TUI difere do IRIS; usando o do IRIS:', tuiInvocationId);
  }
  log('invocationId:', invocationId, '| approvalId:', approvalId);
  await shot(term, 'step-05-opencode-accountblock');

  // A task do Workflow tem Subject "Approval: <ApprovalId>"
  const taskApprovalId = approvalId;

  await gotoWorkflow(portal);
  await shot(portal, 'step-05-opencode-accountblock-user-portal');

  // ---- Step 6: status da invocacao (pending-approval) ----
  log('--- Step 6: GetInvocationStatus ---');
  await typeTerminal(term, `Use the GetInvocationStatus tool with invocationId ${invocationId}`);
  await waitTerminalIdle(term);
  await shot(term, 'step-06-opencode-status');

  // ---- Step 7: rejeitar no User Portal ----
  log('--- Step 7: rejeitar no User Portal ---');
  await gotoWorkflow(portal);
  await selectTask(portal, taskApprovalId);
  await shot(portal, 'step-07-workflow-portal-inbox');

  await clickActionButton(portal, '$Accept');
  await shot(portal, 'step-07-workflow-portal-owned');

  await clickActionButton(portal, 'Reject');
  await waitTaskGone(portal, taskApprovalId);
  await shot(portal, 'step-07-workflow-portal-rejected');

  await typeTerminal(term, `Use the GetInvocationStatus tool with invocationId ${invocationId}`);
  await waitTerminalIdle(term);
  await shot(term, 'step-07-reject');
  log('status da invocacao apos rejeicao:', parseStatusLine(irisSession(STATUS_SCRIPT(invocationId))));

  // ---- Step 8: RiskCheck com CNPJ restrito -> task -> aprovar no portal ----
  log('--- Step 8: RiskCheck restrito ---');
  await typeTerminal(term, PROMPT_RISK_RESTRICTED);
  await waitTerminalIdle(term);
  const riskText = (await readTerminal(term)).text;
  const riskPending = findLatestPendingApproval();
  if (!riskPending) throw new Error('aprovacao pendente do RiskCheck nao encontrada no IRIS');
  const riskInvocationId = riskPending.invocationId;
  const riskApprovalId = riskPending.approvalId;
  log('risk invocationId:', riskInvocationId, '| approvalId:', riskApprovalId);
  await shot(term, 'step-08-restricted-riskcheck');

  await gotoWorkflow(portal);
  await shot(portal, 'step-08-workflow-task');

  await selectTask(portal, riskApprovalId);
  await clickActionButton(portal, '$Accept');
  await clickActionButton(portal, 'Approve');
  await waitTaskGone(portal, riskApprovalId);
  await shot(portal, 'step-08-workflow-portal-approved');

  // A mensagem RiskCheck aparece na producao
  const viewer = await openMessageViewer(context);
  await shot(viewer, 'step-08-restricted-riskcheck-msg');

  await typeTerminal(term, `Use the GetInvocationStatus tool with invocationId ${riskInvocationId}`);
  await waitTerminalIdle(term);
  await shot(term, 'step-08-opencode-status');
  log('status da invocacao apos aprovacao:', parseStatusLine(irisSession(STATUS_SCRIPT(riskInvocationId))));

  log('--- Concluido: ' + shotCount + ' screenshots ---');

  if (!KEEP_OPEN) {
    await context.close();
    await browser.close();
  }
}

main().catch((err) => {
  console.error('ERRO:', err);
  process.exit(1);
});
