---
name: polycron
description: "Use when scheduling one-time or recurring Polydev agent sessions through the operating system scheduler"
---

# Polycron

Polycron schedules agent sessions with the OS scheduler. It is Windows-first and uses `schtasks` on Windows, with crontab support on Linux/macOS.

Scheduled work is still semi-automated: jobs create visible terminal-hosted sessions, write reports/history, and can be inspected through Polydev scripts.

## Storage

```text
~/.polydev/cron/
├── jobs/
└── history.jsonl
```

## Script Path

Use `$POLYDEV_SCRIPTS`:

```bash
"$POLYDEV_SCRIPTS/polycron-list.sh"
```

If unset:

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
```

Windows/Git Bash fallback:

```bash
POLYDEV_SCRIPTS=$(cat ~/.polydev/scripts-path)
SCRIPT_DIR="$POLYDEV_SCRIPTS" bash -c "$(cat "$POLYDEV_SCRIPTS/polycron-list.sh")"
```

## Add Jobs

Recurring:

```bash
"$POLYDEV_SCRIPTS/polycron-add.sh" daily-report \
  --schedule "0 9 * * *" \
  --prompt "Generate daily metrics report" \
  --cwd /path/to/project \
  --report /path/to/report.md
```

One-time:

```bash
"$POLYDEV_SCRIPTS/polycron-add.sh" deploy \
  --at "2026-02-15 14:00" \
  --prompt "Deploy version 2.0" \
  --cwd /path/to/app \
  --type once
```

Parameters:

| Parameter | Required | Meaning |
| --- | --- | --- |
| `<job-id>` | yes | Unique job id |
| `--schedule` | one of schedule/at | Cron-style recurring schedule |
| `--at` | one of schedule/at | Specific date/time |
| `--prompt` | yes | Task prompt for the scheduled agent session |
| `--cwd` | yes | Working directory |
| `--type` | no | `cron` or `once` |
| `--model` | no | Claude Code adapter model flag, default currently `sonnet` |
| `--report` | no | Report path |

`--model` is adapter-specific. Do not treat it as a provider-neutral Polydev field.

## Operate Jobs

```bash
"$POLYDEV_SCRIPTS/polycron-list.sh" --enabled
"$POLYDEV_SCRIPTS/polycron-history.sh" --last 10
"$POLYDEV_SCRIPTS/polycron-history.sh" daily-report --last 5
"$POLYDEV_SCRIPTS/polycron-remove.sh" daily-report
```

Manual trigger for testing:

```bash
"$POLYDEV_SCRIPTS/polycron-trigger.sh" daily-report
```

## Platform Notes

| Platform | Scheduler | Notes |
| --- | --- | --- |
| Windows | `schtasks` | First-class path; simple daily/once schedules are safest |
| Linux/macOS | crontab | Full cron syntax support |

Complex cron expressions may not map perfectly to Windows `schtasks`. Prefer daily or one-time schedules when Windows compatibility matters.

## Security Notes

- Jobs run with the user's permissions.
- Prompts are stored in plain text job JSON.
- Protect `~/.polydev/cron/` if prompts or reports contain sensitive data.

