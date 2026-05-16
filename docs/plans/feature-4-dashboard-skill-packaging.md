# Feature 4: Dashboard Skill Packaging and MVP Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the Polydev dashboard MVP so it can travel with the installed skill directory, monitor an explicit project root, and show actionable task states reliably.

**Architecture:** Keep the dashboard as a sibling of `scripts/` inside the installed Polydev skill directory. The dashboard server must resolve its own skill-local script root from `dashboard/../scripts`, while the project being monitored is passed explicitly through CLI/env/API state instead of inferred from the server cwd. This preserves D1-D4 behavior because backend-specific terminal commands remain in `shell.js` and project paths are supplied by the user for the active runtime.

**Tech Stack:** Node.js, Express, React, Vite, Vitest, Bash wrapper scripts, WezTerm CLI on Windows, tmux on Linux/macOS.

---

## Scope

This plan completes the dashboard MVP. It does not add the larger control-plane features such as sending commands, focusing panes, restoring sessions from the UI, handling `hil` through forms, or rendering Polycron job history. Those should be separate follow-up plans.

## Runtime Dimensions

Any implementation that touches paths or script invocation must keep these dimensions separate:

| Dimension | Runtime | Backend | Shell | Agent | Dashboard implication |
| --- | --- | --- | --- | --- | --- |
| D1 | Windows Codex | WezTerm | PowerShell | Codex CLI | Project root may be `E:\repo`; dashboard can start from skill dir and call WezTerm directly. |
| D2 | Windows ClaudeCode | WezTerm | Git Bash | Claude Code | Project root may be `/e/repo`; dashboard must not require PowerShell or Windows path conversion for task scanning. |
| D3 | Linux/macOS Codex | tmux | bash | Codex CLI | Project root is POSIX; dashboard uses skill-local `scripts/list-sessions.sh` for tmux. |
| D4 | Linux/macOS ClaudeCode | tmux | bash | Claude Code | Same as D3 with `.claude/skills/polydev` as the installed skill root. |

Hard rules:

- Do not reintroduce `~/.polydev/scripts-path`.
- Do not rely on `$POLYDEV_SCRIPTS` or `$env:POLYDEV_SCRIPTS`.
- Do not add PowerShell syntax to shared Bash scripts.
- Do not add Bash requirements to PowerShell-only Codex adapters.
- Do not commit `dashboard/dist` or `dashboard/node_modules`.

## File Map

- Modify `dashboard/server/index.js`
  - Parse project root configuration.
  - Serve `/api/config`.
  - Use the explicit project root for task scanning.
  - Pass configured roots to API functions where needed.
- Modify `dashboard/server/shell.js`
  - Remove `~/.polydev/scripts-path`.
  - Resolve scripts from the skill-local sibling `scripts/` directory.
  - Export small pure helpers for tests.
- Modify `dashboard/server/shell.test.js`
  - Cover script-root resolution and task scanning path behavior.
- Modify `dashboard/src/App.jsx`
  - Fetch dashboard config and pass project root to the view.
- Modify `dashboard/src/components/Dashboard.jsx`
  - Display the monitored project root.
  - Preserve the current sessions/tasks summary.
- Modify `dashboard/src/components/TaskCard.jsx`
  - Preserve `blocked`, `hil`, and `failed` status visibility for orphaned tasks.
- Modify `dashboard/src/App.css`
  - Add visual states for `hil`, `blocked`, and failed/orphaned tasks.
- Modify `scripts/dashboard.sh`
  - Add `--cwd <project-root>`.
  - Export `POLYDEV_PROJECT_ROOT`.
  - Keep dependency install/build behavior optional and local to dashboard.
- Modify `README.md` or `skills/polydev/references/architecture.md`
  - Document dashboard startup from the installed skill directory.
  - Document user-managed `npm install`, `npm run build`, and `node server/index.js` usage.

## Task 1: Project Root Configuration

**Files:**
- Modify: `dashboard/server/index.js`
- Modify: `dashboard/server/shell.js`
- Test: `dashboard/server/shell.test.js`

- [ ] **Step 1: Write failing tests for project root resolution**

Add pure helper tests in `dashboard/server/shell.test.js`:

```js
import { resolveProjectRoot } from './shell.js';

describe('resolveProjectRoot', () => {
  it('uses explicit query/root value first', () => {
    expect(resolveProjectRoot('E:/repo', { env: {}, cwd: 'E:/skill/dashboard' })).toBe('E:/repo');
  });

  it('uses POLYDEV_PROJECT_ROOT when explicit value is absent', () => {
    expect(resolveProjectRoot('', {
      env: { POLYDEV_PROJECT_ROOT: '/home/me/project' },
      cwd: '/home/me/.claude/skills/polydev/dashboard',
    })).toBe('/home/me/project');
  });

  it('falls back to cwd only when no explicit project root exists', () => {
    expect(resolveProjectRoot('', { env: {}, cwd: '/tmp/project' })).toBe('/tmp/project');
  });
});
```

- [ ] **Step 2: Run the targeted test and verify it fails**

Run:

```bash
npm --prefix dashboard test -- server/shell.test.js
```

Expected: fail because `resolveProjectRoot` is not exported.

- [ ] **Step 3: Implement project root helper**

In `dashboard/server/shell.js`, add:

```js
export function resolveProjectRoot(explicitRoot, options = {}) {
  const env = options.env || process.env;
  const cwd = options.cwd || process.cwd();
  return explicitRoot || env.POLYDEV_PROJECT_ROOT || cwd;
}

export function worktreesDirForProject(projectRoot) {
  return resolve(projectRoot, '.worktrees');
}
```

- [ ] **Step 4: Wire `/api/tasks` to the explicit project root**

In `dashboard/server/index.js`, change `/api/tasks` so it resolves:

```js
const projectRoot = resolveProjectRoot(req.query.cwd || req.query.root);
const worktreesDir = worktreesDirForProject(projectRoot);
```

Keep `?dir=` only as a compatibility override if useful:

```js
const worktreesDir = req.query.dir || worktreesDirForProject(projectRoot);
```

- [ ] **Step 5: Add `/api/config`**

Return the project root and inferred worktrees directory:

```js
app.get('/api/config', (req, res) => {
  const projectRoot = resolveProjectRoot(req.query.cwd || req.query.root);
  res.json({ projectRoot, worktreesDir: worktreesDirForProject(projectRoot) });
});
```

- [ ] **Step 6: Run tests**

Run:

```bash
npm --prefix dashboard test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add dashboard/server/index.js dashboard/server/shell.js dashboard/server/shell.test.js
git commit -m "fix(dashboard): use explicit project root for tasks"
```

## Task 2: Skill-Local Script Root

**Files:**
- Modify: `dashboard/server/shell.js`
- Test: `dashboard/server/shell.test.js`

- [ ] **Step 1: Write failing tests for skill-local script resolution**

Add tests:

```js
import { resolveScriptsPath } from './shell.js';

describe('resolveScriptsPath', () => {
  it('defaults to the dashboard sibling scripts directory', () => {
    const scripts = resolveScriptsPath('E:/skill/dashboard/server');
    expect(scripts.replace(/\\/g, '/')).toBe('E:/skill/scripts');
  });

  it('allows an explicit scripts root for tests and advanced callers', () => {
    expect(resolveScriptsPath('ignored', 'E:/custom/scripts')).toBe('E:/custom/scripts');
  });
});
```

- [ ] **Step 2: Run the targeted test and verify it fails**

Run:

```bash
npm --prefix dashboard test -- server/shell.test.js
```

Expected: fail because `resolveScriptsPath` is missing or still reads `~/.polydev/scripts-path`.

- [ ] **Step 3: Replace `getScriptsPath()` implementation**

Remove all reads from `~/.polydev/scripts-path`. Implement:

```js
export function resolveScriptsPath(serverDir, explicitScriptsRoot = '') {
  if (explicitScriptsRoot) return explicitScriptsRoot;
  return resolve(serverDir, '..', '..', 'scripts');
}

let _scriptsPath = null;
export async function getScriptsPath() {
  if (_scriptsPath) return _scriptsPath;
  _scriptsPath = resolveScriptsPath(fileURLToPath(new URL('.', import.meta.url)), process.env.POLYDEV_SCRIPTS_ROOT || '');
  return _scriptsPath;
}
```

`POLYDEV_SCRIPTS_ROOT` is allowed only as an explicit dashboard server override for advanced/manual operation. Do not document it as the normal agent script invocation mechanism.

- [ ] **Step 4: Keep backend behavior unchanged**

Verify these calls remain dimension-safe:

- D1: Windows `listSessions()` should still call `wezterm` directly and not require Bash.
- D2: Windows Claude dashboard on Node still uses WezTerm directly for sessions; task scanning uses the project root.
- D3/D4: Non-Windows `listSessions()` can call skill-local `scripts/list-sessions.sh`.

- [ ] **Step 5: Run tests**

Run:

```bash
npm --prefix dashboard test
```

Expected: all tests pass.

- [ ] **Step 6: Run forbidden-string check**

Run:

```bash
rg -n "scripts-path|SessionStart|POLYDEV_SCRIPTS" dashboard
```

Expected: no matches for `scripts-path` or `SessionStart`; no normal-path reliance on `POLYDEV_SCRIPTS`.

- [ ] **Step 7: Commit**

```bash
git add dashboard/server/shell.js dashboard/server/shell.test.js
git commit -m "fix(dashboard): resolve scripts from skill directory"
```

## Task 3: Dashboard Startup Script

**Files:**
- Modify: `scripts/dashboard.sh`

- [ ] **Step 1: Add argument parsing tests manually by inspection**

Because there is no shell test harness for dashboard yet, keep this task small and verify with direct commands.

- [ ] **Step 2: Add `--cwd <project-root>`**

Update usage:

```bash
# Usage: dashboard.sh [--dev] [--port PORT] [--cwd PROJECT_ROOT]
```

Parse:

```bash
--cwd)
  PROJECT_ROOT="$2"
  shift 2
  ;;
```

Default:

```bash
PROJECT_ROOT="${POLYDEV_PROJECT_ROOT:-$(pwd)}"
```

Export:

```bash
export PORT
export POLYDEV_PROJECT_ROOT="$PROJECT_ROOT"
```

- [ ] **Step 3: Preserve dashboard cwd for npm operations**

Keep `cd "$DASHBOARD_DIR"` before `npm`, `vite`, and `node` commands. The project root must be carried through `POLYDEV_PROJECT_ROOT`, not `process.cwd()`.

- [ ] **Step 4: Validate syntax**

Run:

```bash
bash -n scripts/dashboard.sh
```

Expected: no output, exit code 0.

- [ ] **Step 5: Smoke run API config**

From the repo root, run:

```bash
PORT=3121 bash scripts/dashboard.sh --port 3121 --cwd "$(pwd)"
```

In another terminal or background test, request:

```bash
curl http://localhost:3121/api/config
```

Expected: JSON contains the repo root and `<repo>/.worktrees`.

- [ ] **Step 6: Commit**

```bash
git add scripts/dashboard.sh
git commit -m "feat(dashboard): accept project cwd"
```

## Task 4: Frontend Project Root Display

**Files:**
- Modify: `dashboard/src/App.jsx`
- Modify: `dashboard/src/components/Dashboard.jsx`
- Modify: `dashboard/src/App.css`

- [ ] **Step 1: Add config state**

In `App.jsx`, add:

```js
const [config, setConfig] = useState(null);
```

Fetch `/api/config` in the same refresh flow or a separate effect.

- [ ] **Step 2: Pass config to `Dashboard`**

```jsx
<Dashboard
  sessions={sessions}
  tasks={tasks}
  error={error}
  lastRefresh={lastRefresh}
  config={config}
/>
```

- [ ] **Step 3: Render monitored project root**

In `Dashboard.jsx`, show a compact metadata row:

```jsx
{config?.projectRoot && (
  <div className="project-root">Project: {config.projectRoot}</div>
)}
```

- [ ] **Step 4: Style the row**

Add `.project-root` in `App.css` with small muted text and wrapping for long Windows/POSIX paths.

- [ ] **Step 5: Build**

Run:

```bash
npm --prefix dashboard run build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add dashboard/src/App.jsx dashboard/src/components/Dashboard.jsx dashboard/src/App.css
git commit -m "feat(dashboard): show monitored project root"
```

## Task 5: Actionable Orphaned Status Display

**Files:**
- Modify: `dashboard/src/components/Dashboard.jsx`
- Modify: `dashboard/src/components/TaskCard.jsx`
- Modify: `dashboard/src/App.css`

- [ ] **Step 1: Preserve real task state for orphaned items**

In `Dashboard.jsx`, keep orphaned item task state intact. Do not collapse all states to `ended`.

- [ ] **Step 2: Improve `statusText`**

In `TaskCard.jsx`, replace the orphaned status expression with:

```js
const orphanedStatus = task?.overallStatus || task?.agentStatus || 'ended';
const statusText = orphaned
  ? `${orphanedStatus}${orphanedStatus === 'completed' ? '' : ' (pane lost)'}`
  : task
    ? `${task.overallStatus || ''} / ${task.agentStatus || status}`
    : status;
```

If `overallStatus` is `blocked`, `hil`, or `failed`, it must be visible.

- [ ] **Step 3: Improve dot class**

Map states intentionally:

```js
const importantState = task?.overallStatus || task?.agentStatus;
const dotClass = orphaned
  ? (importantState || 'ended')
  : task
    ? (task.agentStatus || task.overallStatus || 'pending')
    : (status === 'alive' ? 'active' : 'dead');
```

- [ ] **Step 4: Add CSS states**

In `App.css`, add:

```css
.dot.blocked, .dot.failed { background: #f85149; }
.dot.hil { background: #d29922; }
.card-type.blocked, .card-type.failed { background: #3d1214; color: #f85149; }
.card-type.hil { background: #3a2f1f; color: #d29922; }
```

- [ ] **Step 5: Build**

Run:

```bash
npm --prefix dashboard run build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add dashboard/src/components/Dashboard.jsx dashboard/src/components/TaskCard.jsx dashboard/src/App.css
git commit -m "fix(dashboard): preserve actionable orphaned task states"
```

## Task 6: Documentation for Skill-Carried Dashboard

**Files:**
- Modify: `README.md`
- Modify: `skills/polydev/references/architecture.md`

- [ ] **Step 1: Document dashboard location**

Add that dashboard is expected to travel beside `scripts/` in the installed Polydev skill directory:

```text
<polydev-skill-root>/
├── scripts/
└── dashboard/
```

- [ ] **Step 2: Document manual user startup**

Include examples:

```bash
cd /path/to/polydev/dashboard
npm install
npm run build
POLYDEV_PROJECT_ROOT=/path/to/project node server/index.js
```

For the wrapper:

```bash
"/path/to/polydev/scripts/dashboard.sh" --cwd /path/to/project --port 3120
```

PowerShell example for D1:

```powershell
Set-Location "C:\Users\<user>\.codex\skills\polydev\dashboard"
npm install
npm run build
$env:POLYDEV_PROJECT_ROOT = "E:\repo"
node server/index.js
```

- [ ] **Step 3: Document what is not included**

State that v1 dashboard is monitor/read/close only. Send command, focus, restore, and Polycron views are future control-plane features.

- [ ] **Step 4: Run documentation grep**

Run:

```bash
rg -n "dashboard|POLYDEV_PROJECT_ROOT|dashboard.sh|npm run build" README.md skills/polydev/references/architecture.md
```

Expected: new usage is discoverable.

- [ ] **Step 5: Commit**

```bash
git add README.md skills/polydev/references/architecture.md
git commit -m "docs(dashboard): document skill-carried startup"
```

## Task 7: Final Verification

**Files:**
- Modify as needed based on failures.

- [ ] **Step 1: Run dashboard tests**

Run:

```bash
npm --prefix dashboard test
```

Expected: all tests pass.

- [ ] **Step 2: Run dashboard build**

Run:

```bash
npm --prefix dashboard run build
```

Expected: production build succeeds.

- [ ] **Step 3: Run shell syntax check**

Run:

```bash
bash -n scripts/dashboard.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Run forbidden legacy path check**

Run:

```bash
rg -n "scripts-path|SessionStart|POLYDEV_SCRIPTS" dashboard scripts/dashboard.sh README.md skills/polydev/references/architecture.md
```

Expected: no legacy `scripts-path` or `SessionStart` references. `POLYDEV_PROJECT_ROOT` is allowed; `POLYDEV_SCRIPTS` is not.

- [ ] **Step 5: Manual API smoke**

Start the server with an explicit project root:

```bash
PORT=3121 POLYDEV_PROJECT_ROOT="$(pwd)" node dashboard/server/index.js
```

Request:

```bash
curl http://localhost:3121/api/config
curl http://localhost:3121/api/tasks
curl http://localhost:3121/api/sessions
```

Expected:

- `/api/config` shows the repo root and repo `.worktrees`.
- `/api/tasks` returns JSON, even when `.worktrees` is absent.
- `/api/sessions` returns JSON or a clear backend error.

- [ ] **Step 6: Manual browser smoke if browser tooling is available**

Open:

```text
http://localhost:3121
```

Expected:

- Page title is `Polydev Dashboard`.
- Project root is visible.
- No frontend console errors.

- [ ] **Step 7: Confirm no residual server process**

After smoke tests, stop the dashboard server and inspect for leftover Node processes before reporting success.

- [ ] **Step 8: Final commit if fixes were needed**

```bash
git add <changed-files>
git commit -m "fix(dashboard): stabilize skill-packaged MVP"
```

## Completion Criteria

- [ ] Dashboard can be run from its installed skill directory while monitoring an explicit project root.
- [ ] `/api/tasks` scans the monitored project root, not `dashboard/.worktrees`.
- [ ] Dashboard no longer reads `~/.polydev/scripts-path`.
- [ ] Skill-local `dashboard/../scripts` is the default scripts root.
- [ ] `blocked`, `hil`, and failed task states remain visible for orphaned tasks.
- [ ] `npm --prefix dashboard test` passes.
- [ ] `npm --prefix dashboard run build` passes.
- [ ] `bash -n scripts/dashboard.sh` passes.
- [ ] Documentation explains user-managed `npm install`, build, and startup.
