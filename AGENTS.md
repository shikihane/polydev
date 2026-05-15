# AGENTS.mdThis file provides guidance to coding agents working in this repository.## Project OverviewPolydev is an agent orchestration toolkit for parallel development. It uses Git worktrees plus terminal sessions to let multiple coding agents work on independent branches at the same time, with progress coordinated through `task.toon` files.The design should remain agent-tool neutral. Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, and similar coding agents should be able to use the same worktree, terminal, status, and intervention model through thin adapters.Cross-platform terminal backends:- Linux/macOS: tmux, using an isolated socket at `/tmp/polydev.sock`- Windows: WezTerm## PurposePolydev exists to make large coding tasks easier to split, supervise, and recover. Its primary job is not to replace the human engineer; it is to turn parallel agent work into visible, inspectable branches with clear status and cheap intervention points.The project should help a human coordinator:- Decompose a larger request into independent implementation or investigation tracks.- Launch those tracks in isolated Git worktrees without losing the ability to inspect each terminal.- Keep work status explicit through `task.toon` instead of relying on hidden agent state.- Step into a running session when an agent is blocked, needs a `hil` decision, or is drifting.- Reuse the same orchestration model across different coding agents and terminal backends.## Core CapabilitiesPolydev provides orchestration primitives rather than a single opaque workflow:- Worktree-backed coding sessions for independent branches.- Read-only investigation sessions for research, debugging, and codebase analysis.- Background terminal sessions for builds, tests, servers, and long-running commands.- Polling and status coordination through `task.toon` files.- Terminal capture and command injection for human intervention.- Session restore, close, and cleanup paths for recovery.- Polycron scheduling for recurring or delayed agent runs.- Provider adapters for agent-specific launch commands while keeping shared concepts agent-neutral.## Product DirectionPolydev should grow into a practical control plane for multi-agent development. The long-term direction is a tool that can coordinate several coding agents, preserve human oversight, and make partial progress easy to inspect, merge, pause, resume, or discard.Future work should strengthen these properties:- Windows-first reliability for WezTerm, PowerShell, path handling, and visible session recovery.- Agent-neutral adapters so new providers can be added without changing the core workflow model.- Better status dashboards and diagnostics that explain what each agent is doing and why it stopped.- Safer intervention flows for `blocked`, `hil`, failing tests, crashed panes, and stale worktrees.- Durable scheduling and audit history for repeated tasks through Polycron.- Clear verification levels so teams can choose between fast docs-only runs and deeper test coverage.The vision is semi-automated parallel development that stays understandable. Polydev should make it normal to run several agents at once while still knowing where every change lives, what each agent believes it is doing, and how to take control when needed.## Design PrinciplesPolydev is Windows-first. Linux/macOS support matters, but many agent orchestration tools already assume Unix-like terminals; this project should treat Windows and WezTerm as first-class design targets rather than compatibility afterthoughts.Polydev is semi-automated and human-intervenable. It should automate repetitive orchestration, session handling, polling, and scheduling, while keeping the human able to inspect terminal state, send commands, resolve `hil` decisions, recover sessions, and stop or redirect work.Avoid designing opaque full automation. Prefer workflows that expose state, make intervention cheap, and leave clear recovery paths.Avoid baking one agent vendor into core concepts. Keep provider-specific launch commands, model flags, environment variables, and prompt wrappers at the adapter/script boundary.## Repository Layout```textpolydev/├── commands/                  # Agent command entry points│   └── polydev-brainstorm.md  # /polydev-brainstorm task decomposition├── skills/                    # Agent workflow instructions│   ├── using-polydev/         # Entry point and skill selection guide│   ├── polydev/               # Main orchestration skill│   ├── writing-plans/         # Implementation plan generation│   ├── worktree-executor/     # Sub-agent execution in worktrees│   ├── terminal-task-runner/  # Background command hosting│   ├── polycron/              # Scheduled task automation│   └── agent-investigator/    # Read-only investigation agents├── scripts/                   # Runtime scripts; call root wrappers by full absolute path│   ├── adapters/              # Provider-specific launchers│   │   └── codex/windows/     # Codex CLI PowerShell implementation│   └── backends/              # Platform terminal backends│       └── windows/           # WezTerm PowerShell helpers└── templates/                 # Task templates```## Critical Rules

### Four-Dimension Reasoning Rule (MANDATORY)
Polydev must be reasoned about in four explicit runtime dimensions. Whenever a change or recommendation touches spawn, send, path handling, prompt injection, shell syntax, or script invocation, evaluate all four before acting:

| # | Runtime | Backend | Shell | Agent | Correct entry point |
| --- | --- | --- | --- | --- | --- |
| D1 | Windows Codex | WezTerm | PowerShell | Codex CLI | Windows PowerShell adapters by full absolute path such as `C:\Users\<user>\.codex\polydev\scripts\start-codex-investigation.ps1` |
| D2 | Windows ClaudeCode | WezTerm | Git Bash | Claude Code | Bash scripts by full absolute path such as `/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh` |
| D3 | Linux Codex | tmux | bash | Codex CLI | Bash scripts by full absolute path such as `/home/<user>/.codex/polydev/scripts/spawn-codex.sh` |
| D4 | Linux ClaudeCode | tmux | bash | Claude Code | Bash scripts by full absolute path such as `/home/<user>/.claude/skills/polydev/scripts/spawn-session.sh` |

Hard boundary:
- Do not call PowerShell from `.sh` scripts or Bash examples.
- Do not call Bash from `.ps1` scripts or PowerShell examples.
- Pick the correct adapter for the target dimension before launching a session.
- Do not solve D1 by adding PowerShell syntax to shared Bash scripts.
- Do not solve D2/D3/D4 by requiring `pwsh`, Windows paths, or PowerShell cmdlets.

Dimension-specific implications:
- D1 uses Windows-native paths such as `E:\foo\bar` and PowerShell syntax.
- D2 uses Git Bash paths such as `/e/foo/bar` and Claude Code's file tools.
- D3 uses POSIX paths such as `/home/.../foo` and bash syntax for Codex.
- D4 uses POSIX paths and Claude Code's file tools.
- `Set-Content -Path <p> -Value <v>` is acceptable PowerShell guidance for D1, but do not claim positional `Set-Content <path> <value>` binds in reverse.

Before proposing or making a fix, state which dimensions it affects and why the other dimensions still work.

### Script Path
Agents must resolve the Polydev scripts root once when the agent first needs Polydev, then carry that resolved directory as plain prompt/context text. The scripts root is the installed skill directory for the current runtime, and the scripts must travel with the skill directory itself. Do not point runtime calls at a repository checkout, a workspace-relative path, a generated link back into the repo, or any path inferred from the source tree. Do not rely on `$env:POLYDEV_SCRIPTS`, `$POLYDEV_SCRIPTS`, shell profiles, process environment inheritance, or any other runtime variable to transmit the path. After the first resolution, every script call must hard-code the full absolute script path by directly appending the script filename to the resolved scripts directory. The prompt/context should contain a literal fact such as `Polydev scripts root: C:\Users\<user>\.codex\polydev\scripts`, `Polydev scripts root: /c/Users/<user>/.claude/skills/polydev/scripts`, `Polydev scripts root: /home/<user>/.codex/polydev/scripts`, or `Polydev scripts root: /home/<user>/.claude/skills/polydev/scripts`. For ClaudeCode dimensions D2 and D4, the resolved scripts root must be the installed Claude skill directory (`.claude/skills/polydev/scripts`), not a repository checkout, `.claudecode`, or any cache-based install path. If Polydev is upgraded and that literal path becomes stale, let the script call fail clearly; the human can resolve the path again.

Codex on Windows (D1, PowerShell):
```powershell
pwsh -NoProfile -File "C:\Users\<user>\.codex\polydev\scripts\start-codex-investigation.ps1" research -Prompt "Inspect repository only." -Cwd .
pwsh -NoProfile -File "C:\Users\<user>\.codex\polydev\scripts\start-codex-worktree.ps1" my-project codex-auth .worktrees\codex-auth docs\plans\auth.md
```

ClaudeCode on Windows (D2, Git Bash):
```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-agent.sh" research --prompt "Inspect repository only." --report .agent-reports/research.md --cwd .
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" my-project feature-auth .worktrees/feature-auth docs/plans/auth.md
```

Codex on Linux (D3, bash):
```bash
"/home/<user>/.codex/polydev/scripts/spawn-codex.sh" research --prompt "Inspect repository only." --cwd . --output .agent-reports/codex.md
```

ClaudeCode on Linux (D4, bash):
```bash
"/home/<user>/.claude/skills/polydev/scripts/spawn-session.sh" my-project feature-auth .worktrees/feature-auth docs/plans/auth.md
```

Root-level scripts are the stable public entry points once installed into the skill directory. Provider and platform implementations live under `scripts/adapters/` and `scripts/backends/`; keep root wrappers such as `start-codex-worktree.ps1` working when moving internal files.

### Cross-Platform Script Dependencies
Shared Bash scripts must remain cross-platform. Do not add Windows-only dependencies such as `pwsh`, PowerShell cmdlets, `cmd.exe`, Windows path syntax, or WezTerm-only assumptions to generic Bash entry points. PowerShell 7 (`pwsh`) is allowed for Windows-native `*.ps1` adapter scripts and Windows-only backend helpers only.

If shared scripts need JSON parsing, use a cross-platform strategy: prefer an already-required portable tool, a vendored helper that works on supported shells, or backend-specific implementations selected after platform detection. Do not replace Python or shell-native parsing with `pwsh` as a universal Bash-script dependency.

### Verification Failures And Timeouts
Do not dismiss timeouts, hangs, slow commands, interrupted tool calls, orphaned processes, partial output, or surprising verification results as "flaky" or "incidental" without evidence. Investigate until there is a concrete explanation tied to a process, command, environment condition, or code path.

Do not route around a failing check just to produce a green result. If a verification command times out or is interrupted, inspect for leftover processes and stale terminal sessions before rerunning. If a replacement verification is used, explain why the original failure is understood and why the replacement covers the same behavior.

Never report a feature as verified while a related timeout, hang, residual process, or unexplained warning remains unresolved. Document residual risk explicitly if the root cause is outside the repository.

### Workspace Names
The `workspace` parameter controls terminal window grouping. Use one consistent workspace name for parallel tasks in the same project.

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" my-project feature/auth ...
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" my-project feature/api ...
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" my-project feature/ui ...
```

Different workspace names create separate windows.

### Tool-Specific Cost Control
Do not make cost-control rules globally vendor-specific. Put model choices and pricing safeguards in the adapter that launches a given agent.

Claude Code `Task` sub-agents should use `model: "sonnet"` unless the user explicitly requests otherwise. Add equivalent cost controls beside each future adapter instead of making this a core Polydev rule.

### Provider Adapter Boundary
| Provider | Investigation | Worktree | Implementation |
| --- | --- | --- | --- |
| Claude Code | `spawn-agent.sh` | `spawn-session.sh` | bash adapter scripts |
| Codex CLI on Windows | `start-codex-investigation.ps1` | `start-codex-worktree.ps1` | PowerShell adapter scripts |
| Codex CLI on Linux | `spawn-codex.sh` | future adapter | bash adapter scripts |
| Gemini CLI | `spawn-gemini.sh` | future adapter | bash adapter scripts |

The Codex PowerShell adapter defaults to `--sandbox workspace-write --ask-for-approval on-request`. Use `-DangerousBypass` only when the human explicitly requests a fully unattended run. Do not add Codex lifecycle emulation; status is initialized by the launcher and then maintained through explicit `task.toon` updates.

### Status Communication
Sub-agents communicate through `task.toon` files. The main agent monitors with `poll.sh`.

Important statuses:
- `blocked`: main agent may be able to resolve the issue
- `hil`: human-in-the-loop decision required

### Pane IDs
`pane_id` is the primary terminal session identifier.

| Backend | Format | Example |
| --- | --- | --- |
| WezTerm | numeric | `5` |
| tmux | `session:window.pane` | `polydev:1.0` |

Debug output goes to stderr and may include `[D]` prefixes with worktree, branch, or pane context.
## Script ReferenceAll scripts below must be invoked by hard-coding the full resolved absolute path to the script file. Do not invoke them through `$env:POLYDEV_SCRIPTS` or `$POLYDEV_SCRIPTS`.### Core Workflow| Scenario | Script | Parameters || --- | --- | --- || Create worktree-backed agent session | `spawn-session.sh` | `<workspace> <branch> <worktree-path> <plan-file>` || Create Codex worktree session on Windows | `start-codex-worktree.ps1` | `<workspace> <branch> <worktree-path> <plan-file>` || Monitor status loop | `poll.sh` | `<worktrees-dir> <timeout>` || Restore crashed session | `restore-session.sh` | `<worktree-path> [--force]` || Restore Codex worktree session on Windows | `restore-codex-worktree.ps1` | `<worktree-path> [-Force]` |### Session Management| Scenario | Script | Parameters || --- | --- | --- || Send to worktree session | `wo-send-command.sh` | `<worktree-path> "<cmd>" [--peek N]` || Send to any session | `send-to-session.sh` | `<pane_id> "<cmd>" [--peek N]` || Read terminal output | `capture-screen.sh` | `<worktree-path> [--lines N]` or `--pane-id <id>` || List sessions | `list-sessions.sh` | `[workspace]` || Close session | `close-session.sh` | `<worktree-path>` or `--pane-id <id>` |### Background Tasks| Scenario | Script | Parameters || --- | --- | --- || Start background command | `run-background.sh` | `<name> "<cmd>" [--cwd <dir>] [--peek N]` || Start Claude Code session | `spawn-agent.sh` | `<name> --prompt "<task>" --report <path> --cwd <dir> [--peek N]` || Start Codex CLI session | `spawn-codex.sh` | `<name> --prompt "<task>" --cwd <dir> [--model <name>] [--output <path>]` || Start Codex CLI session on Windows | `start-codex-investigation.ps1` | `<name> -Prompt "<task>" -Cwd <dir> [-Output <path>]` || Start Gemini CLI session | `spawn-gemini.sh` | `<name> --prompt "<task>" --cwd <dir> [--output <path>]` |### Scheduled Tasks| Scenario | Script | Parameters || --- | --- | --- || Add scheduled task | `polycron-add.sh` | `<job-id> --schedule "..." --prompt "..." --cwd <dir>` || Remove scheduled task | `polycron-remove.sh` | `<job-id>` || List scheduled tasks | `polycron-list.sh` | `[--all|--enabled|--disabled]` || View task history | `polycron-history.sh` | `[job-id] [--last N]` |### Cleanup| Scenario | Script | Parameters || --- | --- | --- || Clean worktree + session | `cleanup-worktree.sh` | `<worktree-path>` |### `--peek`Scripts that return a `pane_id` support `--peek N`.- `--peek 0`: capture immediately- `--peek 5`: wait 5 seconds, then capture- omitted: do not capture```bash"/c/Users/<user>/.claude/skills/polydev/scripts/send-to-session.sh" 5 "docker ps" --peek 3"/c/Users/<user>/.claude/skills/polydev/scripts/run-background.sh" build "npm test" --peek 10```## Development Workflow1. Brainstorm with `/polydev-brainstorm` for task decomposition.2. Plan with `polydev:writing-plans`.3. Execute with `polydev:polydev`.4. Monitor with `poll.sh` and handle `blocked` or `hil` states.5. Verify according to the selected verification level.6. Clean up worktrees only after human confirmation.Use `polydev:using-polydev` to choose the right skill or command for a task.## Verification Levels| Level | Name | Scope || --- | --- | --- || L0 | skip | No verification, suitable for docs/config only || L1 | compile | Build only || L2 | unit | Build plus unit tests || L3 | integration | Integration tests included || L4 | e2e | End-to-end tests included || L5 | manual | Human verification required |## PolycronPolycron schedules agent sessions through OS schedulers.- Linux/macOS: crontab- Windows: schtasksData lives under `~/.polydev/cron/`:- job definitions: `~/.polydev/cron/jobs/`- trigger history: `~/.polydev/cron/history.jsonl`Examples:```bash"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-add.sh" daily-report \  --schedule "0 9 * * *" \  --prompt "Generate daily metrics report" \  --cwd /path/to/project"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-list.sh""/c/Users/<user>/.claude/skills/polydev/scripts/polycron-history.sh" --last 10"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-remove.sh" daily-report```## Windows Notes- Do not add new Python dependencies to shared Bash scripts. If maintaining a legacy path that still invokes Python on Windows, use `python`, not `python3`.- Always quote paths with spaces.- Scripts handle path conversion automatically.- Use PowerShell 7 (`pwsh`) for `*.ps1` Codex adapter scripts.- WezTerm may need a cold-start retry after system boot.## Terminal Backend GuardrailsDo not shorten the `sleep 2` before sending Enter in WezTerm send-text helpers. Interactive coding agents need time to process large text input before Enter is sent.Do not remove `--no-paste` from `wezterm cli send-text` calls. Without it, bracketed paste markers can make Enter arrive as literal text instead of executing the command.The Claude adapter must unset `CLAUDECODE` using shell-appropriate logic. Prefer `tb_launch_claude()` for that adapter instead of sending raw `unset CLAUDECODE && ...` commands. Keep equivalent tool-specific environment handling inside that tool's launcher.## Inline Python EscapingWhen passing shell values to inline Python, use environment variables instead of string interpolation.```bashPANE_ID="$pane_id" $PYTHON -c "import ospid = os.environ.get('PANE_ID', '')"```Avoid:```bash$PYTHON -c "if pid == '$pane_id': ..."```
