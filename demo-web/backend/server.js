const express = require('express');
const axios = require('axios');
const cors = require('cors');
const fs = require('fs');
const { spawn } = require('child_process');

const app = express();
const PORT = 3001;

app.use(cors());
app.use(express.json({ limit: '1mb' }));

const IRIS_BASE = 'http://iris:52773';
const IRIS_WEB_BASE = process.env.IRIS_WEB_BASE || 'http://localhost:52773';
// Same file the OpenCode agent reads (see opencode.json). Never hardcode CNPJs:
// the tutorial step is built from this list at request time.
const RESTRICTED_CNPJS_FILE = process.env.RESTRICTED_CNPJS_FILE || '/app/config/restricted_cnpjs.txt';
const IRIS_ALLOWED_PATHS = [
  '/csp/irisapp/EnsPortal.MessageViewer.zen',
  '/csp/irisapp/_DeepSee.UserPortal.Workflow.zen'
];

const SHELL_BLOCK_PATTERNS = [
  /!/,
  /\brm\b/,
  /\bcurl\b/,
  /\bwget\b/,
  /`/,
  /\$\(/,
  /;/,
  /\|/,
  /&&/,
  />/,
  /</,
  /\bnc\b/,
  /\bnetcat\b/,
  /\bbash\b/,
  /\bsh\b/,
  /\bpython\b/,
  /\bperl\b/,
  /\bruby\b/
];

function isShellCommand(prompt) {
  return SHELL_BLOCK_PATTERNS.some(p => p.test(prompt));
}

function detectTool(prompt) {
  const p = prompt.toLowerCase();
  if (p.includes('paylookup') || p.includes('orderid')) return 'PayLookup';
  if (p.includes('customerupdate') || p.includes('newaddress')) return 'CustomerUpdate';
  if (p.includes('accountblock') || p.includes('blocktype')) return 'AccountBlock';
  if (p.includes('getinvocationstatus') || p.includes('invocationid')) return 'GetInvocationStatus';
  if (p.includes('createworkflowtask')) return 'CreateWorkflowTask';
  if (p.includes('riskcheck') || p.includes('cnpj')) return 'RiskCheck';
  return null;
}

const UUID_RE = '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}';

function extractIds(output) {
  // Handles both `**Invocation ID**: \`UUID\`` and `**Invocation ID:** \`UUID\``,
  // plain text, quoted IDs, etc.
  const grab = label => {
    const re = new RegExp(
      `\\*{0,2}${label}\\s*ID\\*{0,2}\\s*:?\\s*\\*{0,2}\\s*[\\x60"']?(${UUID_RE})`,
      'i'
    );
    const m = output.match(re);
    return m ? m[1] : null;
  };
  return {
    invocationId: grab('Invocation'),
    approvalId: grab('Approval')
  };
}

function readRestrictedCnpjs() {
  try {
    return fs
      .readFileSync(RESTRICTED_CNPJS_FILE, 'utf8')
      .split(/\r?\n/)
      .map(line => line.trim())
      .filter(line => line && !line.startsWith('#'));
  } catch {
    return [];
  }
}

function buildToolArgs(tool, prompt) {
  const p = prompt;
  switch (tool) {
    case 'PayLookup': {
      const m = p.match(/orderid\s+([A-Za-z0-9._-]+)/i);
      const c = p.match(/customerid\s+([A-Za-z0-9._-]+)/i);
      return { OrderId: m ? m[1] : '', CustomerId: c ? c[1] : '' };
    }
    case 'CustomerUpdate': {
      const c = p.match(/customerid\s+([A-Za-z0-9._-]+)/i);
      const a = p.match(/newaddress\s+"([^"]+)"/i) || p.match(/newaddress\s+(\S+)/i);
      return { CustomerId: c ? c[1] : '', NewAddress: a ? (a[1] || a[2]) : '' };
    }
    case 'AccountBlock': {
      const c = p.match(/customerid\s+([A-Za-z0-9._-]+)/i);
      const b = p.match(/blocktype\s+"([^"]+)"/i) || p.match(/blocktype\s+(\S+)/i);
      const r = p.match(/reason\s+"([^"]+)"/i) || p.match(/reason\s+(\S+)/i);
      return { CustomerId: c ? c[1] : '', BlockType: b ? (b[1] || b[2]) : '', Reason: r ? (r[1] || r[2]) : '' };
    }
    case 'GetInvocationStatus': {
      const m = p.match(/invocationid\s+"([^"]+)"/i) || p.match(/invocationid\s+(\S+)/i);
      return { invocationId: m ? (m[1] || m[2]) : '' };
    }
    case 'CreateWorkflowTask': {
      const m = p.match(/pParams\s+"([^"]+)"/i) || p.match(/pParams\s+(\S+)/i);
      return { pParams: m ? (m[1] || m[2]) : '{}' };
    }
    case 'RiskCheck': {
      const c = p.match(/cnpj\s+(\S+)/i);
      const s = p.match(/scope\s+"([^"]+)"/i) || p.match(/scope\s+(\S+)/i);
      return { Cnpj: c ? c[1] : '', Scope: s ? (s[1] || s[2]) : 'full' };
    }
    default:
      return {};
  }
}

// Run `opencode run <prompt>` in its own process group so a timeout can kill
// the whole tree (opencode spawns children that otherwise keep stdout open).
function runOpencode(promptText, timeoutMs = 180000) {
  return new Promise((resolve, reject) => {
    const child = spawn('opencode', ['run', promptText], {
      cwd: '/app',
      detached: true,
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let stdout = '';
    let stderr = '';
    let settled = false;
    const timer = setTimeout(() => {
      try { process.kill(-child.pid, 'SIGKILL'); } catch {}
      finish(reject, Object.assign(new Error('OpenCode request timed out. Please try again.'), { code: 'ETIMEDOUT' }));
    }, timeoutMs);

    function finish(fn, arg) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn(arg);
    }

    child.stdout.on('data', chunk => {
      stdout += chunk;
      if (stdout.length > 10 * 1024 * 1024) {
        try { process.kill(-child.pid, 'SIGKILL'); } catch {}
        finish(reject, new Error('OpenCode output exceeded 10MB.'));
      }
    });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', err => finish(reject, err));
    child.on('close', code => {
      if (code === 0) finish(resolve, stdout);
      else finish(reject, new Error(`OpenCode exited with code ${code}${stderr ? `: ${stderr.slice(0, 500)}` : ''}`));
    });
  });
}

app.post('/api/chat', async (req, res) => {
  const { prompt } = req.body;
  if (!prompt || typeof prompt !== 'string') {
    return res.status(400).json({ error: 'prompt is required' });
  }

  if (isShellCommand(prompt)) {
    return res.status(403).json({ error: 'Shell commands (!, rm, curl, etc.) are not allowed for security reasons.' });
  }

  try {
    const tool = detectTool(prompt);
    const args = tool ? buildToolArgs(tool, prompt) : {};

    // Chamar opencode diretamente (sem shell): evita interpretação de metacharacters
    // e permite matar o processo com SIGKILL caso o modelo demore demais.
    const opencodePrompt = tool
      ? `Use the ${tool} tool with ${Object.entries(args).map(([k, v]) => `${k} ${v}`).join(' ')}`
      : prompt;

    const output = await runOpencode(opencodePrompt);
    const trimmed = output.trim();
    const { invocationId, approvalId } = extractIds(trimmed);
    res.json({ tool, args, output: trimmed, invocationId, approvalId });
  } catch (err) {
    const timedOut = err && (err.signal === 'SIGKILL' || err.code === 'ETIMEDOUT');
    res.status(500).json({
      error: timedOut
        ? 'OpenCode request timed out. Please try again.'
        : (err.message || 'Error executing opencode')
    });
  }
});

app.get('/api/tutorial', (req, res) => {
  const steps = [
    { step: 1, tool: 'List tools', prompt: 'List the available InteropMCP tools in table with tool name and their parameters', expected: 'Tool list with classification' },
    { step: 2, tool: 'PayLookup', prompt: 'Use the PayLookup tool with OrderId 88201 and CustomerId C-1', expected: '_status: ok' },
    { step: 3, tool: 'CustomerUpdate', prompt: 'Use the CustomerUpdate tool with CustomerId 1 and NewAddress "Av. Paulista, 1000 - São Paulo/SP"', expected: '_status: ok' },
    { step: 4, tool: 'AccountBlock', prompt: 'Use the AccountBlock tool with CustomerId 1, BlockType "permanent", and Reason "Restricted CNPJ detected"', expected: '_status: held' },
    { step: 5, tool: 'GetInvocationStatus', prompt: 'Use the GetInvocationStatus tool with invocationId "<INVOCATION_ID>"', expected: 'Status: completed' },
    { step: 6, tool: 'RiskCheck', prompt: 'Check the risk for Cnpj 99.999.999/0001-90 with full scope', expected: '_status: ok' }
  ];

  // Restricted CNPJ step is derived from config/restricted_cnpjs.txt (never hardcoded).
  const restricted = readRestrictedCnpjs();
  if (restricted.length > 0) {
    steps.push({
      step: steps.length + 1,
      tool: 'RiskCheck (restricted CNPJ)',
      prompt: `Check the risk for Cnpj ${restricted[0]} with full scope`,
      expected: '_status: held (requires human approval)'
    });
  }

  res.json(steps);
});

app.get('/api/config', (req, res) => {
  res.json({ irisWebBase: IRIS_WEB_BASE });
});

app.get('/iris/:path*', async (req, res) => {
  const path = req.params.path;
  const fullPath = '/' + path;
  if (!IRIS_ALLOWED_PATHS.includes(fullPath)) {
    return res.status(403).json({ error: 'Access to this IRIS path is not allowed.' });
  }
  try {
    const response = await axios.get(`${IRIS_BASE}${fullPath}`, {
      responseType: 'stream',
      headers: { 'Accept': 'text/html' }
    });
    res.set(response.headers);
    response.data.pipe(res);
  } catch (err) {
    res.status(502).json({ error: 'Error accessing IRIS' });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Backend running on port ${PORT}`);
});
