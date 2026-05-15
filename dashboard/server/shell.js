// server/shell.js
import { exec, execFile } from 'node:child_process';
import { readFile, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// ─── Parsers ───

export function parseSessionsToon(raw) {
  if (!raw || raw.includes('(No sessions found)')) return [];
  return raw
    .split('\n')
    .map((l) => l.replace(/\r$/, ''))
    .filter((l) => l.startsWith('session_id='))
    .map((line) => {
      const kv = Object.fromEntries(
        line.split(',').map((pair) => {
          const eq = pair.indexOf('=');
          return [pair.slice(0, eq), pair.slice(eq + 1)];
        })
      );
      const sid = kv.session_id || '';
      const parts = sid.split(':');
      const firstPart = parts[0] || '';
      // Handle dash-separated type: bg-proj → type 'bg', or wo → type 'wo'
      const prefix = firstPart.includes('-') ? firstPart.split('-')[0] : firstPart;
      // Extract name: wo:workspace:branch.0 → branch, bg-proj:build.0 → build
      const windowPane = (parts.length >= 3 ? parts[2] : parts[1]) || '';
      const name = windowPane.replace(/\.\d+$/, '');
      return {
        sessionId: sid,
        type: prefix,
        name,
        status: kv.status || 'unknown',
        cwd: kv.cwd || '',
        paneId: kv.pane_id || '',
      };
    });
}

function normalizeWezTermCwd(cwd) {
  if (!cwd) return '';
  if (cwd.startsWith('file://')) {
    try {
      return decodeURIComponent(new URL(cwd).pathname).replace(/^\/([A-Za-z]:)/, '$1');
    } catch {
      return cwd.replace(/^file:\/\//, '');
    }
  }
  return cwd;
}

export function parseWezTermSessions(rawJson) {
  if (!rawJson) return [];
  let panes;
  try {
    panes = JSON.parse(rawJson);
  } catch {
    return [];
  }
  if (!Array.isArray(panes)) return [];

  return panes
    .filter((pane) => pane && pane.pane_id !== undefined && pane.pane_id !== null)
    .map((pane) => {
      const paneId = String(pane.pane_id);
      const workspace = pane.workspace || '';
      const rawName = pane.tab_title || pane.title || paneId;
      const name = rawName.replace(new RegExp(`\\s*\\[${paneId}\\]$`), '');
      return {
        sessionId: paneId,
        type: workspace.startsWith('ag-') ? 'ag' : 'wo',
        name,
        status: 'alive',
        cwd: normalizeWezTermCwd(pane.cwd || ''),
        paneId,
      };
    });
}

export function parseTaskToon(content) {
  const metaMatch = content.match(/^meta\{[^}]*\}:\s*\n\s*(.+)$/m);
  const metaParts = metaMatch ? metaMatch[1].split(',') : [];
  const get = (key) => {
    const m = content.match(new RegExp(`^${key}:[ \\t]*(.*)$`, 'm'));
    return m ? m[1].trim() : '';
  };
  return {
    worktree: metaParts[0] || '',
    branch: metaParts[1] || '',
    paneId: metaParts[2] || '',
    created: metaParts[3] || '',
    overallStatus: get('overall_status'),
    agentStatus: get('agent_status'),
    blockingReason: get('blocking_reason'),
    lastUpdate: get('last_update'),
  };
}

// ─── Shell Execution ───

function run(cmd, options = {}) {
  return new Promise((res, reject) => {
    exec(cmd, { encoding: 'utf-8', timeout: 10000, ...options }, (err, stdout, stderr) => {
      if (err) return reject(new Error(stderr || err.message));
      res(stdout);
    });
  });
}

function runArgs(cmd, args, options = {}) {
  return new Promise((res, reject) => {
    execFile(cmd, args, { encoding: 'utf-8', timeout: 10000, ...options }, (err, stdout, stderr) => {
      if (err) return reject(new Error(stderr || err.message));
      res(stdout);
    });
  });
}

export function isValidPaneId(paneId) {
  return typeof paneId === 'string' && /^[\w%.:@-]+$/.test(paneId);
}

export function resolveProjectRoot(explicitRoot, options = {}) {
  const env = options.env || process.env;
  const cwd = options.cwd || process.cwd();
  return explicitRoot || env.POLYDEV_PROJECT_ROOT || cwd;
}

export function worktreesDirForProject(projectRoot) {
  return resolve(projectRoot, '.worktrees');
}

/**
 * Locate the polydev scripts directory.
 * Reads from ~/.polydev/scripts-path (set by SessionStart hook).
 * Falls back to relative path from this file.
 */
let _scriptsPath = null;
export async function getScriptsPath() {
  if (_scriptsPath) return _scriptsPath;
  try {
    const home = process.env.HOME || process.env.USERPROFILE;
    const stored = await readFile(join(home, '.polydev', 'scripts-path'), 'utf-8');
    _scriptsPath = stored.trim();
  } catch {
    // Fallback: relative to this file → ../../scripts
    _scriptsPath = resolve(fileURLToPath(new URL('.', import.meta.url)), '..', '..', 'scripts');
  }
  return _scriptsPath;
}

/**
 * Detect terminal backend: 'wezterm' on Windows, 'tmux' otherwise.
 */
export function getBackend() {
  return process.platform === 'win32' ? 'wezterm' : 'tmux';
}

// ─── API Functions ───

export async function listSessions() {
  const scripts = await getScriptsPath();
  let raw;
  if (getBackend() === 'wezterm') {
    raw = await runArgs('wezterm', ['cli', 'list', '--format', 'json']);
    return parseWezTermSessions(raw);
  }
  raw = await run(`bash "${scripts}/list-sessions.sh"`);
  return parseSessionsToon(raw);
}

export async function listTasks(worktreesDir) {
  const entries = await readdir(worktreesDir, { withFileTypes: true }).catch(() => []);
  const tasks = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const taskFile = join(worktreesDir, entry.name, 'task.toon');
    try {
      const content = await readFile(taskFile, 'utf-8');
      tasks.push(parseTaskToon(content));
    } catch {
      // no task.toon, skip
    }
  }
  return tasks;
}

export async function capturePane(paneId, lines = 50) {
  const backend = getBackend();
  let raw;
  if (backend === 'wezterm') {
    raw = await runArgs('wezterm', [
      'cli', 'get-text', '--pane-id', String(paneId), '--start-line', String(-lines),
    ]);
  } else {
    raw = await runArgs('tmux', [
      '-S', '/tmp/polydev.sock', 'capture-pane', '-t', String(paneId), '-p', '-S', String(-lines),
    ]);
  }
  return raw.split('\n');
}

export async function killPane(paneId) {
  if (!isValidPaneId(String(paneId))) {
    throw new Error('Invalid pane id');
  }
  if (getBackend() === 'wezterm') {
    await runArgs('wezterm', ['cli', 'kill-pane', '--pane-id', String(paneId)], { timeout: 15000 });
    return;
  }
  const scripts = await getScriptsPath();
  await run(`bash "${scripts}/close-session.sh" --pane-id ${paneId}`, { timeout: 15000 });
}

export async function closePane(paneId) {
  const backend = getBackend();
  try {
    if (backend === 'wezterm') {
      await runArgs('wezterm', ['cli', 'kill-pane', '--pane-id', String(paneId)]);
    } else {
      await runArgs('tmux', ['-S', '/tmp/polydev.sock', 'kill-pane', '-t', String(paneId)]);
    }
  } catch {
    // pane may already be gone, that's fine
  }
}

export async function isPaneAlive(paneId) {
  const backend = getBackend();
  try {
    if (backend === 'wezterm') {
      await runArgs('wezterm', [
        'cli', 'get-text', '--pane-id', String(paneId), '--start-line', '0', '--end-line', '0',
      ]);
    } else {
      await runArgs('tmux', [
        '-S', '/tmp/polydev.sock', 'list-panes', '-t', String(paneId),
      ]);
    }
    return true;
  } catch {
    return false;
  }
}
