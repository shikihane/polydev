# Polydev Kanban

Use this reference for the Polydev dashboard/Kanban monitor. It is a read-focused control surface for Polydev sessions and task state.

The dashboard is part of Polydev's semi-automated control-plane direction: it should make session state visible without hiding work behind opaque automation.

## Scope

The v1 dashboard:

- Shows live terminal sessions from WezTerm on Windows or tmux on Linux/macOS.
- Scans `task.toon` files under the monitored project's `.worktrees`.
- Displays the monitored project root and orphaned task states such as `blocked`, `hil`, and `failed`.
- Streams terminal capture for a selected pane through Server-Sent Events.
- Supports closing or killing panes.

The v1 dashboard does not yet:

- Send arbitrary commands to panes.
- Focus panes in the terminal UI.
- Restore worktree sessions.
- Resolve `hil` forms.
- Render Polycron job history.

Those are future control-plane features and should be implemented as explicit follow-up work, not implied by the current dashboard.

## Installed Layout

The dashboard must travel with the installed Polydev skill root:

```text
<polydev-skill-root>/
├── scripts/
└── dashboard/
```

The dashboard server resolves scripts from `dashboard/../scripts` by default. The project to monitor is passed explicitly with `--cwd`, `POLYDEV_PROJECT_ROOT`, or API query state.

The monitored project root and the skill root are separate concepts:

- Skill root: where `dashboard/` and `scripts/` live.
- Project root: the repository whose `.worktrees` and sessions should be shown.

Do not start the server from the project root and expect relative paths to identify the skill package. Do not point dashboard script calls at a repository checkout when running an installed skill.

## Runtime Dimensions

| Dimension | Runtime | Backend | Shell | Path rules |
| --- | --- | --- | --- | --- |
| D1 | Windows Codex | WezTerm | PowerShell | Project root may be `E:\repo`; dashboard can start from the skill dir and call WezTerm directly |
| D2 | Windows Claude Code | WezTerm | Git Bash | Project root may be `/e/repo`; task scanning must not require PowerShell or Windows path conversion |
| D3 | Linux/macOS Codex | tmux | bash | Project root is POSIX; dashboard uses skill-local `scripts/list-sessions.sh` for tmux |
| D4 | Linux/macOS Claude Code | tmux | bash | Project root is POSIX; dashboard uses `.claude/skills/polydev/scripts` |

Do not use repository-relative script paths, agent script-root environment variables, or shell profile path caches.

## Backend Behavior

Dashboard backend logic lives in `dashboard/server/shell.js`.

- `getBackend()` chooses `wezterm` on Windows and `tmux` otherwise.
- On Windows, session listing uses `wezterm cli list --format json` directly.
- On Linux/macOS, session listing calls the skill-local `list-sessions.sh`.
- Pane capture uses `wezterm cli get-text` on Windows and `tmux -S /tmp/polydev.sock capture-pane` elsewhere.
- Closing or killing panes validates `paneId` before calling backend commands.
- `resolveProjectRoot()` uses explicit API input first, then `POLYDEV_PROJECT_ROOT`, then server cwd.
- `worktreesDirForProject()` scans `<projectRoot>/.worktrees`, not `dashboard/.worktrees`.
- `resolveScriptsPath()` defaults to `dashboard/../scripts`.

`POLYDEV_DASHBOARD_SCRIPTS_ROOT` is allowed only as an advanced dashboard server override for script lookup. Do not treat `POLYDEV_DASHBOARD_SCRIPTS_ROOT` as the normal script-root mechanism for agents. Agent-facing script invocation still follows `using-polydev.md`: resolve once from the installed skill path and paste literal absolute paths.

## API Contract

| Endpoint | Purpose | Notes |
| --- | --- | --- |
| `GET /api/config` | Returns `projectRoot` and `worktreesDir` | Accepts `cwd` or `root` query override |
| `GET /api/tasks` | Returns parsed `task.toon` records | Accepts `cwd`, `root`, or `dir`; returns JSON even when `.worktrees` is absent |
| `GET /api/sessions` | Returns live backend sessions | Returns sessions or a clear backend error |
| `POST /api/kill/:paneId` | Kill a pane through the backend | Rejects invalid pane IDs |
| `POST /api/close/:paneId` | Close a pane through the backend | Treats already-closed panes as non-fatal |
| `GET /api/stream/capture/:paneId` | Streams pane capture via SSE | Emits `capture`, `dead`, or `error` events |

Task parsing expects `task.toon` fields such as `overall_status`, `agent_status`, `blocking_reason`, `last_update`, and pane metadata in the `meta{...}` line.

## Startup

Prefer the wrapper when the active runtime has Bash:

```bash
"/path/to/polydev/scripts/dashboard.sh" --cwd /path/to/project --port 3120
```

The wrapper:

- Keeps npm install/build operations inside the dashboard directory.
- Exports `POLYDEV_PROJECT_ROOT` for the server.
- Supports `--dev`, `--port PORT`, and `--cwd PROJECT_ROOT`.
- Builds the frontend when `dashboard/dist` is missing.

For D1 Windows Codex from PowerShell:

```powershell
Set-Location "C:\Users\<user>\.codex\skills\polydev\dashboard"
npm install
npm run build
$env:POLYDEV_PROJECT_ROOT = "E:\repo"
node server/index.js
```

For manual POSIX startup:

```bash
cd /path/to/polydev/dashboard
npm install
npm run build
POLYDEV_PROJECT_ROOT=/path/to/project node server/index.js
```

Open `http://localhost:3120`.

## Verification

Use the dashboard package path that matches the current layout. In this repository, run from the repository root:

```bash
npm --prefix polydev/dashboard test
npm --prefix polydev/dashboard run build
bash -n polydev/scripts/dashboard.sh
```

For an HTTP smoke test:

1. Start the server on a free port with the intended project root.
2. Query `http://localhost:<port>/api/config`; it should show the monitored project root and `<project>/.worktrees`.
3. Query `http://localhost:<port>/api/tasks`; it should return JSON even when `.worktrees` is absent.
4. Query `http://localhost:<port>/api/sessions`; it should return sessions or a clear backend error.
5. Stop the server and inspect for leftover Node processes before reporting completion.

Do not dismiss timeouts, hangs, or partial HTTP responses. Explain the process, command, environment, or code path that caused them before claiming the dashboard is verified.

## Common Mistakes

- Starting the server from `dashboard/` and expecting it to monitor `dashboard/.worktrees`.
- Confusing the installed skill root with the monitored project root.
- Pointing dashboard script calls at a repository checkout instead of the installed skill root.
- Using PowerShell syntax in Bash examples, or Bash syntax in D1 PowerShell examples.
- Treating `POLYDEV_DASHBOARD_SCRIPTS_ROOT` as a general Polydev script-root mechanism.
- Committing `dashboard/dist` or `dashboard/node_modules`.
