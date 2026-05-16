# Investigation Report: Polydev Real D1 Codex Bypass Smoke Test

Generated: 2026-05-16T12:37:18Z

## Summary

The requested Windows PowerShell smoke command ran successfully from E:\Heyang3\polydev. Get-Location reported the expected repository root. Get-ChildItem -LiteralPath AGENTS.md, polydev | Select-Object Name found AGENTS.md and the expected top-level entries under the polydev skill directory. No broader repository investigation, automated tests, or extra verification assets were created.

## Findings

### 1. PowerShell session is rooted at the expected repository path

The smoke command returned the current path as E:\Heyang3\polydev, matching the requested repository context for the D1 Windows Codex runtime.

### 2. Required Polydev guidance and skill directory entries are present

The command listed AGENTS.md plus the expected Polydev skill contents: gents, commands, dashboard, eferences, scripts, 	emplates, and SKILL.md. This confirms the smoke-test-visible files and directories are available from the current checkout.

## Key Files

- AGENTS.md - Repository instructions file discovered by the smoke command.
- polydev/SKILL.md - Polydev skill entry point discovered through the polydev literal path listing.

## Recommendations

1. Treat this as a successful read-only smoke test for the exact requested command.
2. Run real installed-skill runtime checks only when specifically requested, using public root entry scripts by full absolute path.
