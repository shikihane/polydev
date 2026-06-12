# AGENTS.mdThis file provides guidance to coding agents working in this repository.## Project OverviewPolydev is an agent orchestration toolkit for parallel development. It uses Git worktrees plus terminal sessions to let multiple coding agents work on independent branches at the same time, with progress coordinated through `task.toon` files.The design should remain agent-tool neutral. Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, and similar coding agents should be able to use the same worktree, terminal, status, and intervention model through thin adapters.Cross-platform terminal backends:- Linux/macOS: tmux, using an isolated socket at `/tmp/polydev.sock`- Windows: WezTerm## PurposePolydev exists to make large coding tasks easier to split, supervise, and recover. Its primary job is not to replace the human engineer; it is to turn parallel agent work into visible, inspectable branches with clear status and cheap intervention points.The project should help a human coordinator:- Decompose a larger request into independent implementation or investigation tracks.- Launch those tracks in isolated Git worktrees without losing the ability to inspect each terminal.- Keep work status explicit through `task.toon` instead of relying on hidden agent state.- Step into a running session when an agent is blocked, needs a `hil` decision, or is drifting.- Reuse the same orchestration model across different coding agents and terminal backends.## Core CapabilitiesPolydev provides orchestration primitives rather than a single opaque workflow:- Worktree-backed coding sessions for independent branches.- Read-only investigation sessions for research, debugging, and codebase analysis.- Background terminal sessions for builds, tests, servers, and long-running commands.- Polling and status coordination through `task.toon` files.- Terminal capture and command injection for human intervention.- Session restore, close, and cleanup paths for recovery.- Polycron scheduling for recurring or delayed agent runs.- Provider adapters for agent-specific launch commands while keeping shared concepts agent-neutral.## Product DirectionPolydev should grow into a practical control plane for multi-agent development. The long-term direction is a tool that can coordinate several coding agents, preserve human oversight, and make partial progress easy to inspect, merge, pause, resume, or discard.Future work should strengthen these properties:- Windows-first reliability for WezTerm, PowerShell, path handling, and visible session recovery.- Agent-neutral adapters so new providers can be added without changing the core workflow model.- Better status dashboards and diagnostics that explain what each agent is doing and why it stopped.- Safer intervention flows for `blocked`, `hil`, failing tests, crashed panes, and stale worktrees.- Durable scheduling and audit history for repeated tasks through Polycron.- Clear verification levels so teams can choose between fast docs-only runs and deeper test coverage.The vision is semi-automated parallel development that stays understandable. Polydev should make it normal to run several agents at once while still knowing where every change lives, what each agent believes it is doing, and how to take control when needed.## Design PrinciplesPolydev is Windows-first. Linux/macOS support matters, but many agent orchestration tools already assume Unix-like terminals; this project should treat Windows and WezTerm as first-class design targets rather than compatibility afterthoughts.Polydev is semi-automated and human-intervenable. It should automate repetitive orchestration, session handling, polling, and scheduling, while keeping the human able to inspect terminal state, send commands, resolve `hil` decisions, recover sessions, and stop or redirect work.Avoid designing opaque full automation. Prefer workflows that expose state, make intervention cheap, and leave clear recovery paths.Avoid baking one agent vendor into core concepts. Keep provider-specific launch commands, model flags, environment variables, and prompt wrappers at the adapter/script boundary.## Repository Layout
```text
polydev/                       # Installable Polydev skill directory; copy this folder as the skill
├── SKILL.md                   # Main skill entry point and route guide
├── commands/                  # Agent command entry points
│   └── polydev-brainstorm.md  # /polydev-brainstorm task decomposition
├── references/                # Workflow references formerly split into subskills
├── scripts/                   # Runtime scripts; call root wrappers by full absolute path
│   ├── adapters/              # Provider-specific launchers
│   │   └── codex/windows/     # Codex CLI PowerShell implementation
│   └── backends/              # Platform terminal backends
│       └── windows/           # WezTerm PowerShell helpers
├── dashboard/                 # Skill-local dashboard app
├── templates/                 # Task and prompt templates
└── agents/                    # Agent adapter metadata

docs/                          # Planning and historical design notes
```

## Critical Rules

### Real-Machine Verification Only (MANDATORY)
Polydev verification is real-machine only. This project must not rely on repository-local automated test scripts, mocked terminal output, stubbed agents, fake WezTerm/tmux sessions, or unit-style simulations to prove runtime behavior.

Hard boundary:
- Do not create, maintain, or run automated test harnesses as a substitute for real installed-skill verification.
- Do not add a `tests/` directory for Polydev behavior checks.
- Verify runtime behavior only through the affected real dimension: installed skill path, public root entry script, real terminal backend, real shell, and real agent/session where applicable.
- For spawn, send, path handling, prompt injection, readiness, timeout, cleanup, and background-task behavior, inspect actual pane output and session state.
- If real-machine verification is unavailable, report the change as unverified and state the exact missing dimension.

### Four-Dimension Reasoning Rule (MANDATORY)
Polydev must be reasoned about in four explicit runtime dimensions. Whenever a change or recommendation touches spawn, send, path handling, prompt injection, shell syntax, or script invocation, evaluate all four before acting:

| # | Runtime | Backend | Shell | Agent | Correct entry point |
| --- | --- | --- | --- | --- | --- |
| D1 | Windows Codex | WezTerm | PowerShell | Codex CLI | Windows PowerShell adapters by full absolute path such as `C:\Users\<user>\.codex\skills\polydev\scripts\start-codex-investigation.ps1` |
| D2 | Windows ClaudeCode | WezTerm | Git Bash | Claude Code | Bash scripts by full absolute path such as `/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh`; use `/c/Users/<user>/.claude/skills/polydev/scripts/spawn-codex.sh` for Codex CLI investigations |
| D3 | Linux Codex | tmux | bash | Codex CLI | Bash scripts by full absolute path such as `/home/<user>/.codex/skills/polydev/scripts/spawn-codex.sh` |
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
Agents must resolve the Polydev scripts root once when the agent first needs Polydev, then carry that resolved directory as plain prompt/context text. The scripts root is the installed skill directory for the current runtime, and the scripts must travel with the skill directory itself. Do not point runtime calls at a repository checkout, a workspace-relative path, a generated link back into the repo, or any path inferred from the source tree. Do not rely on `$env:POLYDEV_SCRIPTS`, `$POLYDEV_SCRIPTS`, shell profiles, process environment inheritance, or any other runtime variable to transmit the path. After the first resolution, every script call must hard-code the full absolute script path by directly appending the script filename to the resolved scripts directory. The prompt/context should contain a literal fact such as `Polydev scripts root: C:\Users\<user>\.codex\skills\polydev\scripts`, `Polydev scripts root: /c/Users/<user>/.claude/skills/polydev/scripts`, `Polydev scripts root: /home/<user>/.codex/skills/polydev/scripts`, or `Polydev scripts root: /home/<user>/.claude/skills/polydev/scripts`. For ClaudeCode dimensions D2 and D4, the resolved scripts root must be the installed Claude skill directory (`.claude/skills/polydev/scripts`), not a repository checkout, `.claudecode`, or any cache-based install path. If Polydev is upgraded and that literal path becomes stale, let the script call fail clearly; the human can resolve the path again.

Codex on Windows (D1, PowerShell):
```powershell
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\start-codex-investigation.ps1" research -Cwd .
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\send-prompt.ps1" <pane_id> -Text "Inspect repository only." -Peek 5
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\start-codex-worktree.ps1" my-project codex-auth .worktrees\codex-auth docs\plans\auth.md
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\run-background.ps1" build -Command "npm run build" -Cwd .
```

ClaudeCode on Windows (D2, Git Bash):
```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-agent.sh" research --cwd .
"/c/Users/<user>/.claude/skills/polydev/scripts/send-prompt.sh" <pane_id> --file /tmp/research-prompt.md --peek 5
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-codex.sh" codex-research --cwd .
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" my-project feature-auth .worktrees/feature-auth docs/plans/auth.md
```

Codex on Linux (D3, bash):
```bash
"/home/<user>/.codex/skills/polydev/scripts/spawn-codex.sh" research --cwd .
"/home/<user>/.codex/skills/polydev/scripts/send-prompt.sh" <pane_id> --file /tmp/research-prompt.md --peek 5
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
| Claude Code | `spawn-agent.sh` + `send-prompt.sh` | `spawn-session.sh` | bash adapter scripts |
| Codex CLI from Bash | `spawn-codex.sh` + `send-prompt.sh` | future adapter | bash adapter scripts |
| Codex CLI on Windows | `start-codex-investigation.ps1` + `send-prompt.ps1` | `start-codex-worktree.ps1` | PowerShell adapter scripts |
| Codex CLI on Linux | `spawn-codex.sh` | future adapter | bash adapter scripts |
| Gemini CLI | `spawn-gemini.sh` | future adapter | bash adapter scripts |

The Codex PowerShell adapter defaults to `--sandbox workspace-write --ask-for-approval on-request`. Use `-DangerousBypass` only when the human explicitly requests a fully unattended run. Do not add Codex lifecycle emulation. Worktree lifecycle belongs in `task.toon`; investigation lifecycle is visible pane state inspected by capture.

### Status Communication
Worktree sub-agents communicate through `task.toon` files. The main agent monitors worktrees with `poll.sh`. Investigation and background sessions do not require `task.toon`; observe them with `capture-screen.*`, `--peek`, or direct terminal inspection.

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

## Investigation Spawn Contract

`spawn-agent.sh` and `spawn-codex.sh` only start a visible agent TUI, handle trust confirmation when the target cwd matches, wait for a maintainable ready keyword list, and return `pane_id`. They must not accept prompt, report, or output parameters. Send work with `send-prompt.sh`; it sends and returns immediately. Do not make completion waiting part of the default investigation flow. Use `--peek N` or `capture-screen.sh` for observation.

## Script Reference

All scripts below must be invoked by hard-coding the full resolved absolute path to the script file.

| Scenario | Script | Parameters |
| --- | --- | --- |
| Create worktree-backed agent session | `spawn-session.sh` | `<workspace> <branch> <worktree-path> <plan-file>` |
| Monitor status loop | `poll.sh` | `<worktrees-dir> <timeout>` |
| Send to Windows pane | `send-to-session.ps1` | `<pane_id> "<cmd>" [-Peek N] [-NoEnter]` |
| Send to Bash session | `send-to-session.sh` | `<pane_id> "<cmd>" [--peek N]` |
| Read terminal output | `capture-screen.sh` | `<worktree-path> [--lines N]` or `--pane-id <id>` |
| List sessions | `list-sessions.sh` | `[workspace]` |
| Close session | `close-session.sh` | `<worktree-path>` or `--pane-id <id>` |
| Start Windows background command | `run-background.ps1` | `<name> -Command "<cmd>" [-Cwd <dir>] [-Peek N]` |
| Start Bash background command | `run-background.sh` | `<name> "<cmd>" [--cwd <dir>] [--peek N]` |
| Start Claude Code TUI | `spawn-agent.sh` | `<name> --cwd <dir> [--model <name>] [--ready-timeout 15]` |
| Start Codex CLI TUI | `spawn-codex.sh` | `<name> --cwd <dir> [--model <name>] [--ready-timeout 15]` |
| Send agent prompt | `send-prompt.sh` | `<pane_id> (--text <prompt> \| --file <path>) [--peek N]` |
| Capture agent output | `capture-screen.sh` | `--pane-id <id> [--lines N]` |
| Start Windows Codex TUI | `start-codex-investigation.ps1` | `<name> -Cwd <dir> [--model <name>] [--ready-timeout 15]` |
| Send Windows Codex prompt | `send-prompt.ps1` | `<pane_id> (-Text <prompt> \| -File <path>) [-Peek N]` |
| Capture Windows Codex output | `capture-screen.ps1` | `-PaneId <id> [-Lines N]` |
| Add scheduled task | `polycron-add.sh` | `<job-id> --schedule "..." --prompt "..." --cwd <dir>` |

Scripts that return a `pane_id` support `--peek N`.
