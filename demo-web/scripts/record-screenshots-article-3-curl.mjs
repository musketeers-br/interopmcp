#!/usr/bin/env node
/**
 * record-screenshots-article-3-curl.mjs — Captura as telas do artigo 3 para o
 * tutorial via API REST (curl), em vez do terminal do Opencode.
 *
 * Mesmo mecanismos de record-screenshots-article-3.mjs:
 *   - Um único contexto Playwright Chromium headless (1324x736).
 *   - Login do portal IRIS feito em um contexto separado (não gravado) e os
 *     cookies copiados para o contexto de captura (evita "flash" de login).
 *   - Consultas reais no IRIS via "docker exec ... iris session" para achar a
 *     aprovação pendente e ler o status da invocação.
 *   - Cache-buster na navegação do portal para sempre ver conteúdo novo.
 *
 * Diferença: em vez de digitar prompts no terminal, o script chama a API REST
 * do agente (POST /api/agent/assess) com o PDF em Base64, exatamente como o
 * tutorial do artigo mostra.
 *
 * Cada passo produz um PNG em docs/articles/img/ com o padrão
 * article-3-step-<nn>-<slug>.png. As respostas da API sao impressas no
 * console, para servirem de texto ao artigo.
 *
 * Uso: node record-screenshots-article-3-curl.mjs [--no-clean] [--keep-open]
 */

import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'fs';
import { execFileSync } from 'child_process';
import { chromium } from 'playwright';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const REPO_DIR = join(__dirname, '..', '..');
const OUT_DIR = join(REPO_DIR, 'docs', 'articles', 'img');
const INVOICE_DIR = join(REPO_DIR, 'src', 'br', 'musketeers', 'InteropMCP', 'Demo', 'Invoices');
const ARTICLE = 'article-3';

const WIDTH = 1324;
const HEIGHT = 736;

// Stack de teste
const API_BASE = 'http://localhost:52775';
const API_URL = `${API_BASE}/api/agent/assess`;
const PORTAL_BASE = API_BASE;
const PORTAL_LOGIN_URL = `${PORTAL_BASE}/csp/irisapp/EnsPortal.MessageViewer.zen`;
const WORKFLOW_URL = `${PORTAL_BASE}/csp/irisapp/_DeepSee.UserPortal.Workflow.zen?$NAMESPACE=IRISAPP`;
const MESSAGE_VIEWER_URL = `${PORTAL_BASE}/ui/interop/message-viewer/index.html?%24NAMESPACE=IRISAPP`;

const API_USER = 'mcp_demo';
const PORTAL_USER = '_SYSTEM';
const PORTAL_PASS = 'SYS';
const CONTAINER = 'ai-hub-demo-web-iris-test-1';

const GOAL = 'Evaluate the supplier of the attached document';

// Os dois cenarios do tutorial: o mesmo arquivo, um CNPJ que nao esta na
// lista restrita e um que esta.
const CASES = [
  {
    slug: 'non-restricted',
    pdf: 'INV-2026-119.pdf',
    note: 'CNPJ 63.212.233/0001-78 - nao consta na lista restrita',
  },
  {
    slug: 'restricted',
    pdf: 'INV-2026-120.pdf',
    note: 'CNPJ 12.345.678/0001-95 - consta na lista restrita',
  },
];

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

/// Senha da API: do .env do demo, com o valor conhecido como reserva.
function apiPassword() {
  for (const f of [join(REPO_DIR, 'demo-web', '.env'), join(REPO_DIR, '.env')]) {
    if (!existsSync(f)) continue;
    const m = readFileSync(f, 'utf8').match(/^INTEROPMCP_DEMO_PASSWORD=(.*)$/m);
    if (m) {
      const v = m[1].trim().replace(/^["']|["']$/g, '');
      if (v) return v;
    }
  }
  return 'change-me';
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

// Aprovacao pendente mais recente: <ApprovalId>|<InvocationId>.
const FIND_PENDING_SCRIPT = `
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("SELECT TOP 1 ApprovalId, InvocationId FROM br_musketeers_InteropMCP.Approvals WHERE Decision = 'pending' ORDER BY ID DESC")
Set rs = stmt.%Execute()
Set o = ""
If rs.%Next() Set o = rs.%Get("ApprovalId") _ "|" _ rs.%Get("InvocationId")
Write o, !
Halt
`;

const FIND_OLDEST_PENDING_SCRIPT = `
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("SELECT TOP 1 ApprovalId FROM br_musketeers_InteropMCP.Approvals WHERE Decision = 'pending' ORDER BY ID ASC")
Set rs = stmt.%Execute()
Set found = ""
If rs.%Next() Set found = rs.%Get("ApprovalId")
Write found, !
Halt
`;

const REJECT_SCRIPT = (id) => `
Do ##class(br.musketeers.InteropMCP.Approvals).Reject("${id}", "screenshot-cleanup", "Stale approval rejected by record-screenshots-article-3-curl.mjs cleanup.")
Write "rejected", !
Halt
`;

const CLEAR_WORKLIST_SCRIPT = `
Set stmt = ##class(%SQL.Statement).%New()
Set sc = stmt.%Prepare("DELETE FROM EnsLib_Workflow.Worklist WHERE Task IN (SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE TaskStatus_IsComplete = 0)")
Set removed = stmt.%Execute()
Write "worklist_removed=", removed, !
Halt
`;

function findLatestPendingApproval() {
  const out = irisSession(FIND_PENDING_SCRIPT);
  const m = String(out).match(
    /([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})\|([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})/i
  );
  return m ? { approvalId: m[1], invocationId: m[2] } : null;
}

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

// ---------- API REST ----------

/// Chama POST /api/agent/assess com o PDF em Base64. Devolve o corpo JSON
/// e o codigo HTTP.
function callApi(pdfPath, goal) {
  const b64 = execFileSync('base64', ['-w0', pdfPath], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const payload = JSON.stringify({ Goal: goal, DocumentBase64: b64 });
  const tmp = join('/tmp', `interopmcp-assess-${Date.now()}.json`);
  writeFileSync(tmp, payload);
  const auth = Buffer.from(`${API_USER}:${apiPassword()}`).toString('base64');
  try {
    const out = execFileSync(
      'curl',
      [
        '-sS',
        '-w',
        '\n__HTTP_STATUS__%{http_code}',
        '-X',
        'POST',
        API_URL,
        '-H',
        'Content-Type: application/json',
        '-H',
        `Authorization: Basic ${auth}`,
        '--data-binary',
        `@${tmp}`,
        '--max-time',
        '300',
      ],
      { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }
    );
    const marker = out.lastIndexOf('\n__HTTP_STATUS__');
    const body = out.slice(0, marker);
    const status = out.slice(marker + '\n__HTTP_STATUS__'.length).trim();
    return { status, body };
  } finally {
    rmSync(tmp, { force: true });
  }
}

// ---------- Portal (User Portal) ----------

async function loginForCookies(browser) {
  const loginCtx = await browser.newContext({ colorScheme: 'dark', locale: 'en-US' });
  const lp = await loginCtx.newPage();
  await lp.goto(PORTAL_LOGIN_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(1500);
  if ((await lp.locator('input[name="IRISPassword"]').count()) > 0) {
    await lp.locator('input[name="IRISUsername"]').fill(PORTAL_USER);
    await lp.locator('input[name="IRISPassword"]').fill(PORTAL_PASS);
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
  const fresh = MESSAGE_VIEWER_URL + (MESSAGE_VIEWER_URL.includes('?') ? '&' : '?') + '_=' + Date.now();
  await page.goto(fresh, { waitUntil: 'domcontentloaded', timeout: 60000 });
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

  const results = {};

  // ---- Step 1: PDF com CNPJ nao restrito ----
  const nonRestricted = CASES[0];
  log('--- Step 1: PDF com CNPJ nao restrito (' + nonRestricted.pdf + ') ---');
  {
    const r = callApi(join(INVOICE_DIR, nonRestricted.pdf), GOAL);
    log('HTTP ' + r.status);
    console.log('\n===== RESPOSTA CASO NAO RESTRITO (' + nonRestricted.pdf + ') =====');
    console.log(r.body);
    console.log('===== FIM =====\n');
    results[nonRestricted.slug] = { http: r.status, body: r.body };
  }

  // A mensagem da producao: o RiskCheck rodou.
  const viewer1 = await openMessageViewer(context);
  await shot(viewer1, 'step-06-msg-viewer-non-restricted');
  await viewer1.close();

  // ---- Step 2: PDF com CNPJ restrito ----
  const restricted = CASES[1];
  log('--- Step 2: PDF com CNPJ restrito (' + restricted.pdf + ') ---');
  {
    const r = callApi(join(INVOICE_DIR, restricted.pdf), GOAL);
    log('HTTP ' + r.status);
    console.log('\n===== RESPOSTA CASO RESTRITO (' + restricted.pdf + ') =====');
    console.log(r.body);
    console.log('===== FIM =====\n');
    results[restricted.slug] = { http: r.status, body: r.body };
  }

  const pending = findLatestPendingApproval();
  if (!pending) throw new Error('Aprovacao pendente nao encontrada no IRIS');
  log('invocationId:', pending.invocationId, '| approvalId:', pending.approvalId);

  // ---- Step 3: aprovar no User Portal ----
  log('--- Step 3: aprovar no User Portal ---');
  const portal = await openPortalPage(context);
  await shot(portal, 'step-06-workflow-inbox');

  await selectTask(portal, pending.approvalId);
  await shot(portal, 'step-06-workflow-task');

  await clickActionButton(portal, '$Accept');
  await clickActionButton(portal, 'Approve');
  await waitTaskGone(portal, pending.approvalId);
  await shot(portal, 'step-06-workflow-approved');

  // A invocacao armazenada e reproduzida: o RiskCheck roda na producao.
  await sleep(6000);
  const status = parseStatusLine(irisSession(STATUS_SCRIPT(pending.invocationId)));
  log('status da invocacao apos aprovacao:', status);

  // ---- Step 4: a mensagem do RiskCheck reproduzido ----
  const viewer2 = await openMessageViewer(context);
  await shot(viewer2, 'step-06-msg-viewer-after-approval');
  await viewer2.close();

  // Resumo para o artigo
  console.log('\n===== RESUMO =====');
  console.log('case nao restrito: HTTP ' + results[nonRestricted.slug].http);
  console.log('case restrito:    HTTP ' + results[restricted.slug].http);
  console.log('invocationId (restrito): ' + pending.invocationId);
  console.log('approvalId  (restrito): ' + pending.approvalId);
  console.log('status apos aprovacao:  ' + status);
  console.log('================\n');

  writeFileSync(join('/tmp', 'article-3-curl-responses.json'), JSON.stringify(results, null, 2));

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
