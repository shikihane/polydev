# Polydev Kanban

Use this reference for the Polydev dashboard/Kanban monitor. It is a read-focused control surface for Polydev sessions and task state.

## Scope

- Shows live terminal sessions from WezTerm on Windows or tmux on Linux/macOS.
- Scans `task.toon` files under the monitored project's `.worktrees`.
- Displays the monitored project root and orphaned task states such as `blocked`, `hil`, and `failed`.
- Supports closing panes.
- Does not yet send commands, focus panes, restore sessions, resolve `hil` forms, or render Polycron history.

## Installed Layout

The dashboard must travel with the installed Polydev skill root:

```text
<polydev-skill-root>/
├── scripts/
└── dashboard/
```

The dashboard server resolves scripts from `dashboard/../scripts`. The project to monitor is passed explicitly with `--cwd`, `POLYDEV_PROJECT_ROOT`, or API query state.

## Runtime Dimensions

- D1 Windows Codex: PowerShell + WezTerm. Use Windows paths such as `E:\repo`; do not require Git Bash.
- D2 Windows Claude Code: Git Bash + WezTerm. Use Git Bash paths such as `/e/repo` when launching Bash wrappers.
- D3 Linux/macOS Codex: bash + tmux. Use POSIX paths and the skill-local `scripts/`.
- D4 Linux/macOS Claude Code: bash + tmux. Use POSIX paths and `.claude/skills/polydev/scripts`.

Do not use repository-relative script paths, script-root environment variables, or shell profile path caches.

## Startup

Prefer the wrapper when the active runtime has Bash:

```bash
"/path/to/scripts/dashboard.sh" --cwd /path/to/project --port 3120
```

For D1 Windows Codex from PowerShell:

```powershell
Set-Location "C:\Users\<user>\.codex\polydev\dashboard"
npm install
npm run build
$env:POLYDEV_PROJECT_ROOT = "E:\repo"
node server/index.js
```

For manual POSIX startup:

```bash
cd /path/to/dashboard
npm install
npm run build
POLYDEV_PROJECT_ROOT=/path/to/project node server/index.js
```

Open `http://localhost:3120`.

## Checks

- `curl http://localhost:3120/api/config` should show the monitored project root and `<project>/.worktrees`.
- `curl http://localhost:3120/api/tasks` should return JSON even when `.worktrees` is absent.
- `curl http://localhost:3120/api/sessions` should return sessions or a clear backend error.
- Stop the server and check for leftover Node processes before reporting completion.

## Common Mistakes

- Starting the server from `dashboard/` and expecting it to monitor `dashboard/.worktrees`.
- Pointing dashboard script calls at a repository checkout instead of the installed skill root.
- Using PowerShell syntax in Bash examples, or Bash syntax in D1 PowerShell examples.
- Committing `dashboard/dist` or `dashboard/node_modules`.
