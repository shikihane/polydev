# Writing Implementation Plans

Write self-contained implementation plans for agents that may have no prior context. Plans should be decision-complete, bite-sized, verifiable, and usable by Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, or another executing agent.

## Plan Location

Save plans to `docs/plans/YYYY-MM-DD-<feature-name>.md` or to `PLAN.md` in a worktree root when preparing direct execution.

## Required Header

Every plan starts with:

```markdown
# [Feature Name] Implementation Plan

> **For the executing agent:** Execute this plan task-by-task using `polydev:worktree-executor`.
> **Target adapter:** [Codex CLI / Cursor / OpenCode / Claude Code / Gemini CLI / unspecified]

**Goal:** [One sentence]
**Architecture:** [2-3 sentences]
**Tech Stack:** [Key technologies]
**Verification Level:** [L0-L5]

**Verification Commands:**
- Build: `...`
- Test: `...`
- Lint: `...`

---
```

If the adapter is unknown, write `unspecified`; do not assume Claude Code.

## Task Shape

Each task should be small enough for one focused agent batch:

```markdown
### Task 1: [Name]

**Files:**
- Modify: `path/to/file`
- Test: `path/to/test`

**Steps:**
1. Write the failing test or smallest verification first.
2. Run the command and record expected failure.
3. Implement the minimal change.
4. Run verification and record expected success.
5. Commit if the plan requires per-task commits.
```

Mark dependencies explicitly:

```markdown
**Depends on:** Task 1
**Reason:** Needs the shared interface added there.
```

## Plan Principles

- Use exact file paths and commands.
- Include expected verification outcomes.
- Keep changes minimal and scoped.
- Preserve Windows compatibility when command syntax or paths matter.
- Include `hil` decision points when human approval, credentials, or ambiguous product choices are expected.
- Evaluate D1/D2/D3/D4 separately when the plan touches spawn, send, path handling, prompt injection, shell syntax, or script invocation.

## Required Ending

```markdown
## Verification Checklist

- [ ] Build succeeds: `...`
- [ ] Tests pass: `...`
- [ ] Lint passes: `...`
- [ ] Manual verification, if L5: [...]

## Rollback Plan

If verification fails:
1. Preserve logs and current diff.
2. Identify whether the issue is code, environment, or cross-branch dependency.
3. Fix if local and clear; otherwise set `blocked` or `hil` with reason.
```

## Polydev Handoff

Spawn execution with the adapter for the target runtime.

D2 Windows Claude Code:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
```

D1 Windows Codex:

```powershell
pwsh -NoProfile -File "C:\Users\<user>\.codex\skills\polydev\scripts\start-codex-worktree.ps1" <workspace> <branch> <worktree-path> <plan-file>
```

The worktree executor reads `PLAN.md`, updates `task.toon`, commits work, and stops at `hil` checkpoints for human intervention.
