# Verification Levels

## Overview

Each task in a parallel implementation plan must specify a verification level. This keeps quality gates explicit across independent branches and prevents agents from silently replacing hard checks with easier ones.

Polydev verification is real-machine only. Do not create, maintain, or run repository-local automated tests, mocked terminal output, stubbed agents, or fake terminal sessions to prove Polydev runtime behavior.

Verification level is a contract, not a suggestion. If a command times out, hangs, is interrupted, or produces surprising warnings, investigate and document the concrete cause before reporting that level complete.

## Verification Level Definitions

| Level | Name | Verification Scope | Use Case |
| --- | --- | --- | --- |
| L0 | skip | No verification | Docs, comments, config-only changes |
| L1 | compile | Build or syntax/parse checks only | Minor changes, formatting, low-risk refactoring |
| L2 | focused | Build plus focused real-machine checks | Regular features, utilities, focused bug fixes |
| L3 | integration | L2 plus real installed-skill integration checks | Module interaction, adapters, API endpoints |
| L4 | e2e | L3 plus real terminal/backend end-to-end checks | Core user flows, terminal/backend workflows, critical paths |
| L5 | manual | Real-machine checks plus human verification | Cannot automate, credentials, security-critical behavior, hardware/manual UI |

## Choosing a Level

- Use L0 only when there is genuinely nothing executable to verify.
- Use L1 for syntax, parse, or build confidence when behavior is unchanged.
- Use L2 for most code changes.
- Use L3 when behavior crosses module, process, adapter, filesystem, or network boundaries.
- Use L4 when the user-facing workflow must be exercised end to end.
- Use L5 when a human decision, credential, hardware state, or visual/manual judgment is required.

Do not downgrade verification just to avoid a slow or failing command. If the requested level is not feasible in the current environment, record what was attempted, why it could not complete, and what residual risk remains.

## Verification Commands Format

Every plan should specify concrete commands:

```markdown
**Verification Commands:**
- Build: `npm run build`
- Lint: `npm run lint`
```

For Polydev changes, choose commands that match the changed surface:

- Shell scripts: public installed entry scripts in the affected runtime dimension.
- PowerShell adapters: PowerShell parse checks or `-WhatIf` dry runs where supported.
- Dashboard: build plus real dashboard startup/browser smoke when requested.
- Documentation/reference changes: direct text inspection plus any affected real-machine smoke.

## Verification Checklist Template

```markdown
## Verification Checklist

- [ ] Build succeeds: `...`
- [ ] Lint passes: `...`
- [ ] Manual verification, if L5: [specific steps]
```

## Timeout and Failure Rules

- Do not dismiss timeouts, hangs, interrupted tool calls, orphaned processes, partial output, or surprising verification results as incidental without evidence.
- Do not route around a failing check just to produce a green result.
- If a verification command times out or is interrupted, inspect for leftover processes and stale terminal sessions before rerunning.
- If a replacement verification is used, explain why the original failure is understood and why the replacement covers the same behavior.
- Do not report a level as complete while a related timeout, hang, residual process, or unexplained warning remains unresolved.

## Rollback Plan

Include rollback instructions for verification failures:

```markdown
## Rollback Plan

If verification fails:
1. Preserve logs and current diff.
2. Identify whether the issue is code, environment, cross-branch dependency, or terminal/backend state.
3. Fix if local and clear; otherwise set `blocked` or `hil` with a precise reason.
```

Avoid destructive cleanup unless the human explicitly approves it. In Polydev worktrees, close the session before removing the worktree.

## Default Workflow by Level

| Level | Workflow |
| --- | --- |
| L0 | Explain why verification is skipped |
| L1 | Build or parse check -> inspect output -> report |
| L2 | Build -> focused real-machine check -> inspect output -> report |
| L3 | Build -> real installed-skill integration check -> inspect output -> report |
| L4 | Build -> real terminal/backend e2e check -> inspect output -> report |
| L5 | Real-machine checks -> preserve evidence -> request or record human verification |
