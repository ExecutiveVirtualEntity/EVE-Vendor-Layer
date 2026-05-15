const express = require('express');
const { WebSocketServer } = require('ws');
const pty = require('node-pty');
const http = require('http');

// --- Config ---
const PORT = 3000;
const SECRET_TOKEN = '$haredBr@in2026';
const COOLDOWN_MS = 3000;

// --- Start persistent terminal ---
const shell = pty.spawn('bash', [], {
  name: 'xterm-256color',
  cols: 220,
  rows: 50,
  cwd: '/home/eve/remote',
  env: {
    ...process.env,
    TERM: 'xterm-256color',
    COLORTERM: 'truecolor',
    TERM_PROGRAM: 'vscode',
  }
});

// --- State ---
const clients = new Map();
let controlledBy = null;
let cooldownUntil = 0;

// --- Health check state ---
let claudeHealthy = true;
let healthCheckTimer = null;

// --- Broadcast helpers ---
function broadcast(obj) {
  const msg = JSON.stringify(obj);
  clients.forEach((_, ws) => {
    if (ws.readyState === 1) ws.send(msg);
  });
}

function broadcastControlState() {
  clients.forEach((info, ws) => {
    const isMine = controlledBy === info.name;
    ws.send(JSON.stringify({
      type: 'control',
      controlledBy,
      isMine,
      cooldownUntil
    }));
  });
}

function startClaude() {
  shell.write('cd /home/eve/EveBrain && claude --dangerously-skip-permissions');
  setTimeout(() => { shell.write('\r'); }, 500);
}

// Kill the current Claude process and relaunch in bypass mode.
// Used by the health check (when Claude stops responding) and by the
// /reset-claude endpoint (manual reset from the web UI).
function restartClaude(reason) {
  console.log(`[Restart] Restarting Claude — reason: ${reason || 'unspecified'}`);
  shell.write('\x03');
  setTimeout(() => { shell.write('\x03'); }, 200);
  setTimeout(() => {
    startClaude();
    console.log('[Restart] Claude relaunched in bypass mode');
  }, 3000);
}

function runHealthCheck() {
  if (controlledBy) {
    console.log('[Health] Skipping check - terminal in use by', controlledBy);
    return;
  }
  console.log('[Health] Checking if Claude is responsive...');
  claudeHealthy = false;

  shell.write('echo CLAUDE_HEALTH_OK\n');

  healthCheckTimer = setTimeout(() => {
    if (!claudeHealthy) {
      restartClaude('health check timeout');
    } else {
      console.log('[Health] Claude is healthy');
    }
  }, 30000);
}

// --- Auto-compact state ---
// Polls Claude Code's `/context` slash command on a schedule. When the
// reported context-window usage crosses AUTO_COMPACT_THRESHOLD percent,
// silently fires `/compact` so Eve gets summarized before she becomes slow.
// Only runs when (a) no human is in control via the web UI and (b) Claude
// has been idle for IDLE_BEFORE_POLL_MS — never interrupts an in-flight reply.
const AUTO_COMPACT_THRESHOLD = 80;          // percent of context window used
const AUTO_COMPACT_POLL_MS = 10 * 60 * 1000; // poll every 10 minutes
const IDLE_BEFORE_POLL_MS = 60 * 1000;       // require 60s of shell silence
const COMPACT_LOCKOUT_MS = 60 * 1000;        // don't re-trigger compact within 1 min

let lastShellActivityAt = Date.now();
let pendingContextCheck = false;
let contextCheckBuffer = '';
let autoCompactInProgress = false;

// --- Stream terminal output to all clients ---
shell.onData((data) => {
  broadcast({ type: 'output', data });
  console.log(data);
  lastShellActivityAt = Date.now();

  if (pendingContextCheck) {
    contextCheckBuffer += data;
  }

  if (data.includes('CLAUDE_HEALTH_OK')) {
    claudeHealthy = true;
    if (healthCheckTimer) clearTimeout(healthCheckTimer);
    console.log('[Health] Claude confirmed healthy');
  }
});

// Strip ANSI escape codes — the TUI is full of color/cursor sequences and we
// just need to grep for the percent number reliably.
function stripAnsi(s) {
  return s.replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, '').replace(/\x1b\][^\x07]*\x07/g, '');
}

function pollContextAndMaybeCompact() {
  if (controlledBy) {
    console.log('[AutoCompact] human in control — skipping');
    return;
  }
  if (pendingContextCheck) return;
  if (autoCompactInProgress) return;
  const idleMs = Date.now() - lastShellActivityAt;
  if (idleMs < IDLE_BEFORE_POLL_MS) {
    console.log(`[AutoCompact] Eve still active (${idleMs}ms idle) — skipping`);
    return;
  }

  console.log('[AutoCompact] polling /context');
  pendingContextCheck = true;
  contextCheckBuffer = '';
  shell.write('/context');
  setTimeout(() => { shell.write('\r'); }, 200);

  // Give Claude up to 8 seconds to render the /context response, then parse.
  setTimeout(() => {
    const raw = stripAnsi(contextCheckBuffer);
    pendingContextCheck = false;

    // Look for a "NN%" near words like "context", "used", or the bar character.
    // Defensive: try several patterns, take the first plausible match.
    const patterns = [
      /context[^\n]*?(\d{1,3})\s*%/i,
      /(\d{1,3})\s*%[^\n]*?(?:used|of context|of window)/i,
      /(\d{1,3})\s*%/,  // fallback: any %
    ];
    let percent = null;
    for (const re of patterns) {
      const m = raw.match(re);
      if (m) { percent = parseInt(m[1], 10); break; }
    }

    if (percent === null || isNaN(percent) || percent < 0 || percent > 100) {
      console.log(`[AutoCompact] could not parse /context output (${raw.length} chars)`);
      return;
    }
    console.log(`[AutoCompact] context usage = ${percent}%`);
    if (percent >= AUTO_COMPACT_THRESHOLD) {
      autoCompactInProgress = true;
      console.log(`[AutoCompact] >= ${AUTO_COMPACT_THRESHOLD}% — firing /compact`);
      shell.write('/compact');
      setTimeout(() => { shell.write('\r'); }, 200);
      setTimeout(() => { autoCompactInProgress = false; }, COMPACT_LOCKOUT_MS);
    }
  }, 8000);
}


// Send initial prompt to make terminal visible immediately
setTimeout(() => {
  shell.write('\n');
}, 500);


// --- Auto-start ---
// NOTE (2026-04-22): removed the standalone `python3 main.py &` auto-start.
// Claude Code spawns the Workspace MCP as its own stdio child, so that line
// produced a duplicate MCP server that (a) grabbed 127.0.0.1:8000 before
// Claude's MCP could bind it, and (b) got SIGTTOU-stopped the moment Claude
// took the PTY foreground — leaving a corpse holding the OAuth callback port.
// Broke OAuth auth flow for new accounts until SIGKILL'd manually.
setTimeout(() => {
  startClaude();
}, 8000);

// --- Health check: start after 2 minutes, run every 15 minutes ---
setTimeout(() => {
  console.log('[Health] Health monitoring started');
  setInterval(runHealthCheck, 900000);
}, 120000);

// --- Auto-compact poller: start after 5 minutes (let Claude warm up), poll every AUTO_COMPACT_POLL_MS ---
setTimeout(() => {
  console.log(`[AutoCompact] Auto-compact monitor started — threshold ${AUTO_COMPACT_THRESHOLD}%, poll every ${AUTO_COMPACT_POLL_MS/60000}min`);
  setInterval(pollContextAndMaybeCompact, AUTO_COMPACT_POLL_MS);
}, 5 * 60 * 1000);

// --- WebSocket server ---
const app = express();
app.use(express.json());
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://localhost`);
  const token = url.searchParams.get('token');
  const name = url.searchParams.get('name') || 'Unknown';

  if (token !== SECRET_TOKEN) {
    ws.close(1008, 'Unauthorized');
    return;
  }

  clients.set(ws, { name });
  console.log(`${name} connected`);

  ws.send(JSON.stringify({
    type: 'control',
    controlledBy,
    isMine: controlledBy === name,
    cooldownUntil
  }));

  ws.on('message', (msg) => {
    try {
      const data = JSON.parse(msg);

      if (data.type === 'ping') return;

      if (data.type === 'input') {
        if (controlledBy === name) {
          shell.write(data.data);
        }
      }

      if (data.type === 'resize') {
        shell.resize(data.cols, data.rows);
      }

      if (data.type === 'take_control') {
        const now = Date.now();
        if (now < cooldownUntil) return;
        const previous = controlledBy;
        controlledBy = name;
        cooldownUntil = now + COOLDOWN_MS;
        console.log(`Control taken by ${name}${previous ? ` (was ${previous})` : ''}`);
        broadcastControlState();

        setTimeout(() => {
          if (ws && ws.readyState === 1) {
            ws.send(JSON.stringify({ type: 'input', data: `Hello Claude, this is ${name} for this session\n` }));
          }
        }, 300);
      }

    } catch (e) {}
  });

  ws.on('close', () => {
    console.log(`${name} disconnected`);
    clients.delete(ws);
    if (controlledBy === name) {
      controlledBy = null;
      broadcastControlState();
    }
  });
});

// --- Google Chat Bot endpoint ---
app.post('/gchat-bot', (req, res) => {
  const chatEvent = req.body;
  console.log('[GChat Bot] Received event');

  const appCommand = chatEvent.chat?.appCommandPayload;
  const cmdId = appCommand?.appCommandMetadata?.appCommandId;
  if (cmdId === 1) {
    res.status(200).json({ text: 'OK' });
    const sender = chatEvent.chat?.user?.displayName || 'Unknown';
    const spaceName = chatEvent.chat?.messagePayload?.space?.name ||
                      appCommand?.space?.name || '';
    console.log(`[GChat Bot] Ask Eve quick command from ${sender}`);
    if (!controlledBy) {
      shell.write(`Eve, ${sender} wants to talk to you in Google Chat space "${spaceName}". First send the 🧠 icon to confirm you have received the Chat request, then please check the latest message in that space and reply appropriately.`);
      setTimeout(() => { shell.write('\r'); }, 500);
    }
    return;
  }
  if (cmdId === 2) {
    res.status(200).json({ text: 'Compacting Eve — back in ~1 minute.' });
    const sender = chatEvent.chat?.user?.displayName || 'Unknown';
    console.log(`[GChat Bot] Compact Eve quick command from ${sender}`);
    setTimeout(() => {
      shell.write('/compact');
      setTimeout(() => { shell.write('\r'); }, 200);
    }, 1500);
    return;
  }
  if (cmdId === 3) {
    res.status(200).json({ text: 'Resetting Eve — back in ~1 minute.' });
    const sender = chatEvent.chat?.user?.displayName || 'Unknown';
    console.log(`[GChat Bot] Reset Eve quick command from ${sender}`);
    setTimeout(() => {
      restartClaude(`chat slash command from ${sender}`);
    }, 1500);
    return;
  }
  if (cmdId === 4) {
    res.status(200).json({ text: 'Rebooting Eve box — back in ~1 minute.' });
    const sender = chatEvent.chat?.user?.displayName || 'Unknown';
    console.log(`[GChat Bot] Reboot Eve Box quick command from ${sender}`);
    setTimeout(() => {
      require('child_process').exec('sudo systemctl reboot', (err) => {
        if (err) console.error('[Reboot] failed:', err);
      });
    }, 1500);
    return;
  }

  res.status(200).json({ text: 'OK' });

  const message = chatEvent.message || chatEvent.chat?.messagePayload?.message;
  const sender = message?.sender?.displayName || chatEvent.chat?.user?.displayName || 'Unknown';
  const text = message?.text || message?.argumentText || '';
  const spaceName = message?.space?.name || chatEvent.chat?.messagePayload?.space?.name || '';

  if (!text.trim()) return;

  console.log(`[GChat Bot] ${sender}: ${text}`);

  if (!controlledBy) {
    shell.write(`Eve, ${sender} just sent you a Google Chat message: "${text}". Please reply in the Google Chat space "${spaceName}" so everyone in the group can see your response. First send the 🧠 icon to confirm receipt, then check the latest message and reply appropriately.`);
    setTimeout(() => { shell.write('\r'); }, 500);
  }
});

// --- Pulse-system wake endpoint (added 2026-04-22 for Phase 3 of pulse) ---
// Local-only: 127.0.0.1 binds via Express; cloudflared only routes /gchat-bot etc.
// Used by ~/.local/eve-tools/pulse_tick.py to inject a pulse-recommendation
// into Eve's terminal as a wake-up prompt.
//
// Request body: { token: SECRET_TOKEN, prompt: "...", source: "pulse_tick" }
// Behavior: skips silently if a human is currently controlling the terminal
// via the web UI (so we never interrupt an interactive session).
app.post('/wake', (req, res) => {
  const { token, prompt, source } = req.body || {};
  if (token !== SECRET_TOKEN) {
    return res.status(401).json({ ok: false, error: 'unauthorized' });
  }
  if (!prompt || typeof prompt !== 'string') {
    return res.status(400).json({ ok: false, error: 'prompt required' });
  }
  if (controlledBy) {
    console.log(`[Wake] skipped — controlled by ${controlledBy} (source=${source || '?'})`);
    return res.status(200).json({ ok: false, skipped: 'controlled_by_human' });
  }
  console.log(`[Wake] firing — source=${source || '?'}, ${prompt.length} chars`);
  shell.write(prompt);
  setTimeout(() => { shell.write('\r'); }, 500);
  return res.status(200).json({ ok: true });
});

// --- Soft reset: /compact (web UI "Compact Memory" button) ---
// POST /compact-claude with { token, name? }
// Sends Claude Code's `/compact` slash command into the PTY. Compacts the
// conversation history — frees context window, keeps Eve alive, preserves
// memory + vault state. Use when she's getting slow but you don't want to
// lose what she knows about the current thread.
app.post('/compact-claude', (req, res) => {
  const { token, name } = req.body || {};
  if (token !== SECRET_TOKEN) {
    return res.status(401).json({ ok: false, error: 'unauthorized' });
  }
  console.log(`[Compact] Soft reset (/compact) requested by ${name || 'unknown'}`);
  shell.write('/compact');
  setTimeout(() => { shell.write('\r'); }, 200);
  return res.status(200).json({ ok: true, message: 'Eve is compacting her conversation — a few seconds.' });
});

// --- Hard reset: kill + relaunch (web UI "Reset Eve" button) ---
// POST /reset-claude with { token, name? }
// Kills the current Claude PTY child and relaunches with --dangerously-skip-permissions.
// Use when Eve is fully unresponsive and a soft compact won't help.
app.post('/reset-claude', (req, res) => {
  const { token, name } = req.body || {};
  if (token !== SECRET_TOKEN) {
    return res.status(401).json({ ok: false, error: 'unauthorized' });
  }
  console.log(`[Reset] Hard reset requested by ${name || 'unknown'}`);
  restartClaude(`manual reset by ${name || 'unknown'}`);
  return res.status(200).json({ ok: true, message: 'Eve is restarting — give her ~10 seconds.' });
});

// --- Serve UI ---
app.use('/logo.jpg', express.static(__dirname + '/logo.jpg'));
app.get('/', (req, res) => {
  res.sendFile(__dirname + '/index.html');
});

server.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
