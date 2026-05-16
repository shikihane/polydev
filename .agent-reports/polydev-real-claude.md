# Investigation Report: Smoke Test

Generated: 2026-05-16T12:23:49Z

## Summary

Smoke test ran `pwd`, then verified `AGENTS.md` and `polydev/` exist in the repo root at `/e/Heyang3/polydev`. Both targets resolved successfully. The shell initially started in `/c/Users/gitbash` (Git Bash default), requiring absolute paths; after the first successful absolute-path command the cwd reset to the repo root. No structural issues found.

## Findings

### 1. Shell CWD Mismatch on Session Start

The bash shell opened in `/c/Users/gitbash` rather than the repo root. `ls -1 AGENTS.md polydev` with relative paths failed until absolute paths were used. After the first successful command the shell cwd was reset to `E:\Heyang3\polydev`.

### 2. Target Files Present

`AGENTS.md` and `polydev/` both exist at the repo root and are accessible. The `ls -1 ... >/dev/null` check exited 0.

## Key Files

- `/e/Heyang3/polydev/AGENTS.md` - repo-wide source of truth
- `/e/Heyang3/polydev/polydev/` - skill and reference directory

## Recommendations

1. Investigation prompts should use absolute paths or `cd` to the repo root before relative-path commands to avoid the Git Bash default-cwd issue.
2. No other action needed — smoke test passed.
