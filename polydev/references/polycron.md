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

Resolve the scripts root once from the installed skill directory for the active runtime, then call Polycron scripts by literal full absolute path.

D2 Windows Claude Code example:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-list.sh"
```

D4 Linux/macOS Claude Code example:

```bash
"/home/<user>/.claude/skills/polydev/scripts/polycron-list.sh"
```

## Add Jobs

Recurring:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-add.sh" daily-report \
  --schedule "0 9 * * *" \
  --prompt "Generate daily metrics report" \
  --cwd /path/to/project \
  --report /path/to/report.md
```

One-time:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-add.sh" deploy \
  --at "2026-02-15 14:00" \
  --prompt "Deploy version 2.0" \
  --cwd /path/to/app \
  --type once
```

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
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-list.sh" --enabled
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-history.sh" --last 10
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-history.sh" daily-report --last 5
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-remove.sh" daily-report
```

Manual trigger for testing:

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/polycron-trigger.sh" daily-report
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
