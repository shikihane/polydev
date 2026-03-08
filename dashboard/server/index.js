// server/index.js
import express from 'express';
import cors from 'cors';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';
import { listSessions, listTasks, capturePane, isPaneAlive, isValidPaneId, killPane, closePane } from './shell.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 3120;

app.use(cors());
app.use(express.json());

// Serve built frontend in production
const distPath = resolve(__dirname, '..', 'dist');
if (existsSync(distPath)) {
  app.use(express.static(distPath));
}

// ─── REST Endpoints ───

app.get('/api/sessions', async (req, res) => {
  try {
    const sessions = await listSessions();
    res.json({ sessions });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/tasks', async (req, res) => {
  try {
    // Look for .worktrees in current working directory
    const worktreesDir = req.query.dir || resolve(process.cwd(), '.worktrees');
    const tasks = await listTasks(worktreesDir);
    res.json({ tasks });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/kill/:paneId', async (req, res) => {
  const { paneId } = req.params;
  if (!isValidPaneId(paneId)) {
    res.status(400).json({ error: 'Invalid paneId format' });
    return;
  }
  try {
    await killPane(paneId);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/close/:paneId', async (req, res) => {
  const { paneId } = req.params;
  if (!isValidPaneId(paneId)) {
    res.status(400).json({ error: 'Invalid paneId format' });
    return;
  }
  try {
    await closePane(paneId);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── SSE Endpoint ───

app.get('/api/stream/capture/:paneId', async (req, res) => {
  const { paneId } = req.params;

  if (!isValidPaneId(paneId)) {
    res.status(400).json({ error: 'Invalid paneId format' });
    return;
  }

  const interval = Math.max(1, Math.min(30, parseInt(req.query.interval, 10) || 3));

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });

  let lastContent = '';
  let alive = true;
  let timer;

  const capture = async () => {
    if (!alive) return;
    try {
      const isAlive = await isPaneAlive(paneId);
      if (!isAlive) {
        res.write(`event: dead\ndata: ${JSON.stringify({ paneId })}\n\n`);
        alive = false;
        clearTimeout(timer);
        res.end();
        return;
      }
      const lines = await capturePane(paneId);
      const content = lines.join('\n');
      if (content !== lastContent) {
        lastContent = content;
        const data = JSON.stringify({ paneId, lines, timestamp: new Date().toISOString() });
        res.write(`event: capture\ndata: ${data}\n\n`);
      }
    } catch (err) {
      res.write(`event: error\ndata: ${JSON.stringify({ error: err.message })}\n\n`);
    }
  };

  await capture();

  const scheduleNext = () => {
    if (!alive) return;
    timer = setTimeout(async () => {
      await capture();
      scheduleNext();
    }, interval * 1000);
  };
  scheduleNext();

  req.on('close', () => {
    alive = false;
    clearTimeout(timer);
  });
});

// Fallback: serve index.html for SPA routing
if (existsSync(distPath)) {
  app.get('*', (req, res) => {
    res.sendFile(resolve(distPath, 'index.html'));
  });
}

app.listen(PORT, () => {
  console.log(`Polydev Dashboard API running on http://localhost:${PORT}`);
});
