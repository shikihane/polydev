# Windows Codex PowerShell Adapter Implementation Plan

> **For the executing agent:** Execute this plan task-by-task using `polydev:worktree-executor`.
> **Target adapter:** Codex CLI

**Goal:** Add a Windows-first Codex adapter that can run Polydev investigation and worktree sessions through native PowerShell plus WezTerm, without forking the Polydev core project.
**Architecture:** Keep Polydev core concepts centralized: worktrees, pane IDs, `task.toon`, polling, capture, cleanup, and dashboard remain shared. Add a Windows PowerShell adapter layer for Codex-specific launch, prompt injection, and recovery while preserving the existing bash/Claude path. Stable root scripts remain public wrappers; Codex/Windows implementation lives under `scripts/adapters/codex/windows/`, and shared Windows terminal helpers live under `scripts/backends/windows/`.
**Tech Stack:** PowerShell 7 (`pwsh`), WezTerm CLI, Codex CLI 0.120.0+, Git, existing Polydev `task.toon` templates and Markdown prompts, Node/Vitest for dashboard verification. The plan was written against local `codex-cli 0.120.0`.
**Verification Level:** L2

**Verification Commands:**
- Syntax: `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\terminal-backend.ps1" -SelfTest`
- Syntax: `pwsh -NoProfile -Command '$null = [scriptblock]::Create((Get-Content -Raw (Join-Path $env:POLYDEV_SCRIPTS "start-codex-worktree.ps1"))); "parse-ok"'`
- Test: `npm --prefix dashboard test`
- Manual Windows smoke: `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-worktree.ps1" polydev-test codex/smoke .worktrees/codex-smoke docs/plans/2026-05-08-windows-codex-powershell-adapter.md -WhatIf`

---

## Executor Setup

Before executing this plan, ensure the shell has `POLYDEV_SCRIPTS` set to the repository script directory:

```powershell
$env:POLYDEV_SCRIPTS = "E:\Heyang3\polydev\scripts"
```

All script execution examples use `$env:POLYDEV_SCRIPTS`. Do not call scripts as `.\scripts\...` or `scripts\...` except when explicitly testing path discovery.

## Implementation Decisions

Use these defaults unless the human explicitly asks for a different policy:

1. **Default Codex autonomy:** default to `--sandbox workspace-write --ask-for-approval on-request`; fully unattended runs may use `--ask-for-approval never` only when explicitly requested.
2. **PowerShell edition:** support PowerShell 7 only. Use `pwsh` in docs, examples, and verification. Do not spend implementation complexity on Windows PowerShell 5.1 compatibility.
3. **Entry point naming:** keep root wrapper names purpose-first: `start-codex-investigation.ps1`, `start-codex-worktree.ps1`, and `restore-codex-worktree.ps1`. Internal implementation files use shorter names under `scripts/adapters/codex/windows/`: `start-investigation.ps1`, `start-worktree.ps1`, and `restore-worktree.ps1`.
4. **Prompt injection method:** recommended method is prompt-file handoff, not multiline paste. The launcher writes a prompt file and sends one short command or starts Codex with a short instruction to read it.
5. **No hooks:** the Codex adapter must not depend on hooks or hook emulation. The launcher sets initial `task.toon` metadata, and all later state changes happen through explicit `task.toon` updates by the running Codex agent or direct recovery scripts.
6. **Dashboard integration:** include Windows-native dashboard migration in the first implementation. The dashboard is small enough to update now, and doing it avoids keeping Git Bash as a hidden dashboard dependency on Windows.

Set `hil` and stop if the implementation requires a different autonomy policy, relies on Codex lifecycle hooks, or needs to delete an existing worktree.

## Non-Goals

- Do not build a Codex hook system.
- Do not emulate Claude `SessionStart` or `Stop` hooks for Codex.
- Do not rely on hidden lifecycle callbacks for status updates.
- Do not make hook behavior part of the shared Polydev core contract.
- Do not support Windows PowerShell 5.1 in this pass.
- Do not change the existing bash/Claude implementation except documentation references and shared dashboard compatibility.
- Do not clean up `.worktrees/*` smoke-test directories without human confirmation.

## File Structure

- Create `scripts/backends/windows/wezterm.ps1`
  - Windows-native WezTerm helpers: create/reuse workspace window, spawn pane, set tab title, send text, capture pane, kill pane, shell/path helpers, optional self-test.
- Create `scripts/terminal-backend.ps1`
  - Compatibility wrapper that dot-sources `scripts/backends/windows/wezterm.ps1`.
- Create `scripts/adapters/codex/windows/start-investigation.ps1`
  - PowerShell-native Codex investigation session launcher, equivalent to current `spawn-codex.sh` but Windows-first.
- Create `scripts/start-codex-investigation.ps1`
  - Compatibility wrapper for the Codex investigation implementation.
- Create `scripts/adapters/codex/windows/start-worktree.ps1`
  - PowerShell-native worktree session launcher for Codex, equivalent in purpose to `spawn-session.sh` but provider-specific.
- Create `scripts/start-codex-worktree.ps1`
  - Compatibility wrapper for the Codex worktree implementation.
- Create `scripts/adapters/codex/windows/restore-worktree.ps1`
  - Restore/restart a Codex worktree session using existing `task.toon` metadata.
- Create `scripts/restore-codex-worktree.ps1`
  - Compatibility wrapper for the Codex restore implementation.
- Create `templates/codex-worktree-prompt.md`
  - Codex-specific supplement that tells Codex to use repo skills when available, read `PLAN.md`, update `task.toon`, commit, and stop at `blocked` or `hil`.
- Create `templates/codex-investigator-prompt.md`
  - Codex-specific investigation prompt with `[AGENT_DONE]` output marker.
- Modify `README.md`
  - Document Windows Codex PowerShell path and default approval policy.
- Modify `AGENTS.md`
  - Add adapter boundary guidance for Codex PowerShell and keep `$POLYDEV_SCRIPTS` guidance for bash scripts.
- Modify `skills/using-polydev/SKILL.md`
  - Add Codex PowerShell entry point selection.
- Modify `skills/polydev/SKILL.md`
  - Add worktree Codex adapter examples.
- Modify `skills/polydev/references/architecture.md`
  - Add provider adapter matrix and Windows PowerShell backend notes.
- Modify `dashboard/server/shell.js`
  - Remove hidden Windows dependency on bash for list/kill operations by using WezTerm directly on Windows.
- Modify `dashboard/server/shell.test.js`
  - Cover Windows-native session parsing and direct WezTerm command paths where practical.

## Shared Implementation Notes

- PowerShell scripts should start with `#requires -Version 7.0`.
- Launcher scripts that support dry runs should use `[CmdletBinding(SupportsShouldProcess)]` and honor native `-WhatIf` instead of inventing a separate dry-run convention.
- Use `Join-Path`, `Resolve-Path`, `[System.IO.Path]::GetFullPath()`, and `Convert-Path` where appropriate. Do not shell out to `cygpath`.
- Send text and Enter to WezTerm as separate `wezterm cli send-text --no-paste` calls, with the existing 2 second delay before Enter.
- The last stdout line of launchers should remain script-friendly: the numeric `pane_id` when a real session starts.
- TOON-style status logs should stay on stdout with `[I] event=...`; errors should go to stderr with `[E] error=...`.
- When updating `task.toon`, preserve the existing template shape from `templates/task.toon.template`.

## Task 1: Add PowerShell WezTerm Backend Helpers

**Files:**
- Create: `scripts/backends/windows/wezterm.ps1`
- Create: `scripts/terminal-backend.ps1`

**Steps:**
1. Write a self-test scaffold first:
   - Add `#requires -Version 7.0` and `param([switch]$SelfTest)`.
   - If `-SelfTest` is passed, validate required functions exist and print `self-test-ok`.
2. Implement `Get-PolydevWezTermPanes`.
   - Use `wezterm cli list --format json`.
   - Return an empty array if WezTerm has no panes.
3. Implement `New-PolydevPane`.
   - Parameters: `Workspace`, `TabTitle`, `Cwd`.
   - Reuse an existing window in the same workspace when present.
   - Otherwise spawn a new window with `--new-window --workspace`.
   - Always call `wezterm cli set-tab-title --pane-id <id> "<tab> [<id>]"`.
4. Implement `Send-PolydevText`.
   - Send text and Enter as separate `wezterm cli send-text --no-paste` calls.
   - Preserve the current 2 second delay before Enter.
5. Implement `Get-PolydevPaneText`, `Test-PolydevPaneAlive`, and `Close-PolydevPane`.
6. Implement path helpers:
   - `Resolve-PolydevFullPath`
   - `ConvertTo-PolydevWindowsPath`
   - Do not require Git Bash or `cygpath`.
7. Implement small internal helpers:
   - `Write-PolydevInfo` for `[I] event=...` logs.
   - `Write-PolydevError` for `[E] error=...` stderr logs.
   - `Assert-PolydevCommand` for checking `wezterm`, `git`, and `codex` when a launcher needs them.
8. Run:
   - `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\backends\windows\wezterm.ps1" -SelfTest`
   - `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\terminal-backend.ps1" -SelfTest`
   - Expected: `self-test-ok`.
9. Commit:
   - `git add scripts/backends/windows/wezterm.ps1 scripts/terminal-backend.ps1`
   - `git commit -m "feat(windows): add PowerShell terminal backend"`

## Task 2: Add Codex Prompt Templates

**Files:**
- Create: `templates/codex-worktree-prompt.md`
- Create: `templates/codex-investigator-prompt.md`

**Steps:**
1. Create `templates/codex-worktree-prompt.md`.
   - Include: read `PLAN.md`, execute tasks, update `task.toon`, commit completed changes, set `blocked` or `hil` with `blocking_reason`, set `completed` at the end.
   - Include a Codex-specific instruction: use project/repo skills if available, but the prompt itself is sufficient if skills do not load.
2. Create `templates/codex-investigator-prompt.md`.
   - Mirror `templates/investigator-prompt.md`.
   - Keep `[AGENT_DONE]` marker.
3. Verify templates contain no Claude-only language:
   - `rg -n "Claude|CLAUDE|claude" templates\codex-*.md`
   - Expected: no output.
4. Verify the worktree prompt mentions these exact `task.toon` states:
   - `in_progress`
   - `blocked`
   - `hil`
   - `completed`
5. Commit:
   - `git add templates/codex-worktree-prompt.md templates/codex-investigator-prompt.md`
   - `git commit -m "feat(codex): add Codex prompt templates"`

## Task 3: Add PowerShell Codex Investigation Launcher

**Files:**
- Create: `scripts/adapters/codex/windows/start-investigation.ps1`
- Create: `scripts/start-codex-investigation.ps1`
- Modify: `scripts/backends/windows/wezterm.ps1`

**Steps:**
1. Write argument parsing:
   - Required: `Name`, `-Prompt`, `-Cwd`.
   - Optional: `-Output`, `-Workspace`, `-Model`, `-Sandbox`, `-Approval`, `-DangerousBypass`, `-Peek`.
   - Use `[CmdletBinding(SupportsShouldProcess)]` so PowerShell supplies `-WhatIf`.
2. Implement output path normalization using PowerShell path APIs.
3. Create a WezTerm pane in workspace `ag-<workspace>`.
4. Write the final investigation prompt to a temp file under `$env:TEMP\polydev-prompts`.
   - If `-Output` is provided, include the normalized report path in the generated prompt.
   - If `-Output` is omitted, keep the behavior equivalent to `spawn-codex.sh`: no report path is enforced.
5. Start Codex with a short prompt:
   - Default: `codex --cd "<cwd>" --sandbox workspace-write --ask-for-approval on-request --no-alt-screen "Read <prompt-file> and follow all instructions in it."`
   - If `-DangerousBypass`: replace sandbox/approval with `--dangerously-bypass-approvals-and-sandbox`.
   - If `-Model` is set: add `--model <model>`.
6. Emit TOON-style logs equivalent to `spawn-codex.sh`.
7. `-WhatIf` behavior:
   - Print planned pane metadata, prompt-file path, and Codex command.
   - Do not create a pane.
   - Do not start Codex.
8. Run parse verification:
   - `pwsh -NoProfile -Command '$null = [scriptblock]::Create((Get-Content -Raw (Join-Path $env:POLYDEV_SCRIPTS "start-codex-investigation.ps1"))); "parse-ok"'`
   - Expected: `parse-ok`.
9. Run manual dry smoke:
   - `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-investigation.ps1" smoke -Prompt "Inspect repository only." -Cwd . -WhatIf`
   - Expected: TOON logs and the Codex command, no pane created.
10. Commit:
   - `git add scripts/adapters/codex/windows/start-investigation.ps1 scripts/start-codex-investigation.ps1 scripts/backends/windows/wezterm.ps1`
   - `git commit -m "feat(codex): add PowerShell investigation launcher"`

## Task 4: Add PowerShell Codex Worktree Launcher

**Files:**
- Create: `scripts/adapters/codex/windows/start-worktree.ps1`
- Create: `scripts/start-codex-worktree.ps1`
- Modify: `scripts/backends/windows/wezterm.ps1`

**Depends on:** Task 1, Task 2

**Steps:**
1. Implement parameters:
   - Positional: `Workspace`, `BranchName`, `WorktreePath`, `PlanFile`.
   - Optional: `-VerifyLevel L2`, `-VerifyFallback L1`, `-VerifyCommands`, `-Model`, `-Sandbox`, `-Approval`, `-DangerousBypass`, `-Peek`.
   - Use `[CmdletBinding(SupportsShouldProcess)]` so PowerShell supplies `-WhatIf`.
2. Validate:
   - `PlanFile` exists.
   - `WorktreePath` is not an existing file.
   - Warn if worktree path is not under `.worktrees`.
3. Create or reuse git worktree:
   - Try `git worktree add <path> -b <branch>`.
   - Fallback to `git worktree add <path> <branch>`.
   - In `-WhatIf`, print the intended git command but do not create or modify the worktree.
4. Copy plan to `PLAN.md` if missing.
5. Initialize `task.toon` from `templates/task.toon.template`.
   - Use PowerShell string replacement, not shell `sed`.
   - Preserve the existing TOON shape exactly.
   - Preserve any existing `task.toon` by creating `.task_backups\task.toon.<timestamp>.bak` before mutation.
6. If `task.toon` already has a live pane ID, log `session_already_running` and exit.
7. Create WezTerm pane with workspace name unchanged and tab title equal to branch name.
8. Update `task.toon` pane ID and set:
   - `agent_status: active`
   - `overall_status: pending` until Codex receives prompt.
9. Write Codex worktree prompt to temp file.
10. Launch Codex using:
   - `codex --cd "<worktree>" --sandbox workspace-write --ask-for-approval on-request --no-alt-screen "Read <prompt-file> and follow all instructions in it."`
11. Emit TOON logs equivalent to `spawn-session.sh`, but with `codex_started`.
12. Add `-WhatIf` dry run.
13. Run parse verification:
   - `pwsh -NoProfile -Command '$null = [scriptblock]::Create((Get-Content -Raw (Join-Path $env:POLYDEV_SCRIPTS "start-codex-worktree.ps1"))); "parse-ok"'`
   - Expected: `parse-ok`.
14. Run manual dry smoke:
   - `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-worktree.ps1" polydev-test codex/smoke .worktrees/codex-smoke docs/plans/2026-05-08-windows-codex-powershell-adapter.md -WhatIf`
   - Expected: TOON logs, no worktree created when `-WhatIf` is used.
15. Commit:
   - `git add scripts/adapters/codex/windows/start-worktree.ps1 scripts/start-codex-worktree.ps1 scripts/backends/windows/wezterm.ps1`
   - `git commit -m "feat(codex): add PowerShell worktree launcher"`

## Task 5: Add Codex Session Restore

**Files:**
- Create: `scripts/adapters/codex/windows/restore-worktree.ps1`
- Create: `scripts/restore-codex-worktree.ps1`

**Depends on:** Task 4

**Steps:**
1. Implement parameters:
   - Required: `WorktreePath`.
   - Optional: `-Force`, `-Model`, `-Sandbox`, `-Approval`, `-DangerousBypass`.
   - Use `[CmdletBinding(SupportsShouldProcess)]` so PowerShell supplies `-WhatIf`.
2. Read `task.toon` metadata.
3. If old pane is alive and `-Force` is absent, stop with a clear error.
4. If `-Force` is present, kill old pane through `Close-PolydevPane`.
5. Create a new pane in the recorded workspace and branch.
6. Replace old pane ID in `task.toon`.
7. Relaunch Codex with the same worktree prompt-file strategy.
8. Run parse verification:
   - `pwsh -NoProfile -Command '$null = [scriptblock]::Create((Get-Content -Raw (Join-Path $env:POLYDEV_SCRIPTS "restore-codex-worktree.ps1"))); "parse-ok"'`
   - Expected: `parse-ok`.
9. Commit:
   - `git add scripts/adapters/codex/windows/restore-worktree.ps1 scripts/restore-codex-worktree.ps1`
   - `git commit -m "feat(codex): add PowerShell session restore"`

## Task 6: Migrate Dashboard Windows Operations to Native WezTerm

**Files:**
- Modify: `dashboard/server/shell.js`
- Modify: `dashboard/server/shell.test.js`

**Depends on:** Task 1

**Steps:**
1. Update `listSessions()` so Windows uses direct `wezterm cli list --format json` through `runArgs`, matching the existing parser output shape.
   - Add a pure parser such as `parseWezTermSessions(rawJson)` so unit tests can cover conversion without needing WezTerm installed.
   - Convert each WezTerm pane to `{ sessionId, type, name, status, cwd, paneId }`.
   - For workspace names beginning with `ag-`, use type `ag`; otherwise use type `wo`.
   - Use `tab_title` with a trailing ` [<pane_id>]` stripped as the session name.
2. Keep Linux/macOS behavior using `bash "<scripts>/list-sessions.sh"` for now.
3. Update `killPane()` so Windows calls `wezterm cli kill-pane --pane-id <id>` directly instead of `bash close-session.sh`.
   - Validate `paneId` with `isValidPaneId()` before invoking a process.
4. Preserve `closePane()`, `capturePane()`, and `isPaneAlive()` direct WezTerm behavior.
5. Add or update tests in `dashboard/server/shell.test.js` for:
   - parsing WezTerm numeric pane IDs
   - preserving tmux pane IDs
   - rejecting unsafe pane IDs
   - Windows list-session JSON conversion if the current test structure allows mocking
   - `killPane()` rejecting unsafe pane IDs without shell invocation if dependency injection/mocking already exists; otherwise cover `isValidPaneId()` and parser behavior only.
6. Run:
   - `npm --prefix dashboard test`
   - Expected: all tests pass.
7. Commit:
   - `git add dashboard/server/shell.js dashboard/server/shell.test.js`
   - `git commit -m "feat(dashboard): use native WezTerm operations on Windows"`

## Task 7: Document Adapter Selection and Windows Usage

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `skills/using-polydev/SKILL.md`
- Modify: `skills/polydev/SKILL.md`
- Modify: `skills/polydev/references/architecture.md`

**Steps:**
1. Add a provider adapter matrix:
   - Claude Code: existing `.sh` launcher.
   - Codex CLI investigation: Windows `start-codex-investigation.ps1`.
   - Codex CLI worktree: Windows `start-codex-worktree.ps1`.
2. Document that Windows Codex PowerShell scripts are called with `pwsh` directly, while existing bash scripts remain called through `$POLYDEV_SCRIPTS`.
   - PowerShell examples should use `$env:POLYDEV_SCRIPTS`.
   - Bash examples should continue to use `"$POLYDEV_SCRIPTS/..."`.
3. Add examples:
   - Investigation: `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-investigation.ps1" research -Prompt "..." -Cwd .`
   - Worktree: `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-worktree.ps1" my-project codex/auth .worktrees/codex-auth docs/plans/auth.md`
4. Document approval defaults and the dangerous bypass policy.
5. Run:
   - `rg -n "start-codex-worktree|start-codex-investigation|PowerShell|pwsh" README.md AGENTS.md skills`
   - Expected: new references appear in the right docs.
6. Commit:
   - `git add README.md AGENTS.md skills/using-polydev/SKILL.md skills/polydev/SKILL.md skills/polydev/references/architecture.md`
   - `git commit -m "docs(codex): document Windows PowerShell adapter"`

## Task 8: Verification and Compatibility Pass

**Files:**
- Modify as needed based on verification failures.

**Depends on:** Tasks 1-7

**Steps:**
1. Run PowerShell parse checks:
    - `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\backends\windows\wezterm.ps1" -SelfTest`
    - `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\terminal-backend.ps1" -SelfTest`
   - `pwsh -NoProfile -Command '$null = [scriptblock]::Create((Get-Content -Raw (Join-Path $env:POLYDEV_SCRIPTS "start-codex-investigation.ps1"))); "start-codex-investigation-parse-ok"'`
   - `pwsh -NoProfile -Command '$null = [scriptblock]::Create((Get-Content -Raw (Join-Path $env:POLYDEV_SCRIPTS "start-codex-worktree.ps1"))); "start-codex-worktree-parse-ok"'`
   - `pwsh -NoProfile -Command '$null = [scriptblock]::Create((Get-Content -Raw (Join-Path $env:POLYDEV_SCRIPTS "restore-codex-worktree.ps1"))); "restore-codex-worktree-parse-ok"'`
2. Run dashboard tests:
   - `npm --prefix dashboard test`
   - Expected: all Vitest tests pass.
3. Run documentation grep:
   - `rg -n "Claude adapter|Codex adapter|start-codex-worktree|PowerShell|pwsh" README.md AGENTS.md skills docs`
4. Manual smoke if WezTerm and Codex are installed:
   - `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-investigation.ps1" smoke -Prompt "Say READY and do not edit files." -Cwd . -Peek 5`
   - Expected: pane starts, Codex runs in the current repo, no files modified.
5. Manual worktree smoke if user approves creating a test worktree:
   - `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\start-codex-worktree.ps1" polydev-smoke codex/smoke .worktrees/codex-smoke docs/plans/2026-05-08-windows-codex-powershell-adapter.md -Peek 5`
   - Expected: worktree exists, `task.toon` has numeric pane ID, pane is alive.
6. If manual smoke creates a worktree, do not clean it up without human confirmation.
7. Commit any fixes:
   - `git add <changed-files>`
   - `git commit -m "fix(codex): stabilize Windows PowerShell adapter"`

## Verification Checklist

- [ ] PowerShell backend self-test succeeds through implementation and wrapper:
  - `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\backends\windows\wezterm.ps1" -SelfTest`
  - `pwsh -NoProfile -File "$env:POLYDEV_SCRIPTS\terminal-backend.ps1" -SelfTest`
- [ ] PowerShell launchers parse without syntax errors.
- [ ] Dashboard tests pass: `npm --prefix dashboard test`
- [ ] Dashboard Windows paths use WezTerm directly instead of bash script wrappers.
- [ ] Existing bash/Claude scripts remain untouched except documentation references.
- [ ] Codex investigation smoke starts a visible WezTerm pane on Windows.
- [ ] Codex worktree smoke initializes `task.toon` and stores a numeric pane ID.
- [ ] Documentation explains when to use `.sh` vs `.ps1`.

## Rollback Plan

If verification fails:
1. Preserve terminal output, Codex command line, and current diff.
2. Identify whether failure is in WezTerm interaction, Codex CLI flags, PowerShell path handling, or `task.toon` mutation.
3. Fix local script issues if clear.
4. If Codex CLI behavior differs from `codex-cli 0.120.0`, set `blocked` with the exact version and failing command.
5. If the issue is an autonomy or dangerous bypass policy choice, set `hil` and ask for human decision.
6. Do not delete any created `.worktrees/*` directory until the human confirms cleanup.
