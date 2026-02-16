---
name: polycron
description: Scheduled task automation - Schedule Claude agents to run at specific times using OS-level schedulers (crontab/schtasks). Supports single-run and recurring tasks with full CRUD operations.
version: 0.1.1
---

# Polycron - Scheduled Task Automation

Schedule Claude agents to execute tasks at specific times using OS-level schedulers.

---

## Overview

Polycron integrates with your operating system's native scheduler:
- **Linux/macOS**: crontab
- **Windows**: schtasks

When a scheduled time arrives, the OS triggers `polycron-trigger.sh`, which spawns a Claude agent using `spawn-agent.sh` to execute the task.

---

## Data Storage

```
~/.polydev/cron/
├── jobs/
│   ├── <job-id>.json       # Job definitions
│   └── ...
└── history.jsonl           # Trigger history log
```

---

## Script Path Detection

**At the start of this session, read the polydev scripts path:**

```bash
cat ~/.polydev/scripts-path
# Example output: /home/user/.claude/plugins/cache/polydev-marketplace/polydev/1.4.0/scripts
```

**Remember the full absolute path from the output above, then use it directly in all commands.**

Example:
```bash
# ✓ CORRECT - Use full path directly
/path/to/polydev/scripts/polycron-add.sh daily-report --schedule "0 9 * * *" --prompt "Generate report" --cwd /path/to/project

# ✗ WRONG - Do not use variables
"$POLYDEV_SCRIPTS/polycron-add.sh" ...
```

> **Note**: If `~/.polydev/scripts-path` doesn't exist, polydev is not installed.

---

## CRUD Operations

### Add Job

**Script**: `polycron-add.sh`

**Syntax**:
```bash
# Recurring task (cron schedule)
/path/to/polydev/scripts/polycron-add.sh <job-id> \
  --schedule "0 9 * * *" \
  --prompt "Daily report generation" \
  --cwd /path/to/project \
  [--type cron] \
  [--model sonnet] \
  [--report /path/to/report.md]

# Single-run task (specific date/time)
/path/to/polydev/scripts/polycron-add.sh <job-id> \
  --at "2026-02-15 10:00" \
  --prompt "Deploy to production" \
  --cwd /path/to/project \
  [--type once] \
  [--model sonnet] \
  [--report /path/to/report.md]
```

**Parameters**:
| Parameter | Required | Description |
|-----------|----------|-------------|
| `<job-id>` | Yes | Unique identifier for the job |
| `--schedule` | Yes* | Cron schedule (e.g., "0 9 * * *" = 9am daily) |
| `--at` | Yes* | Specific date/time (e.g., "2026-02-15 10:00") |
| `--prompt` | Yes | Task description for Claude agent |
| `--cwd` | Yes | Working directory for the agent |
| `--type` | No | `cron` (recurring) or `once` (single-run). Default: `cron` |
| `--model` | No | Claude model to use. Default: `sonnet` |
| `--report` | No | Path to save agent output. Default: `~/.polydev/cron/reports/<job-id>.md` |

*Either `--schedule` or `--at` is required, not both.

**Cron Schedule Format**:
```
* * * * *
│ │ │ │ │
│ │ │ │ └─ Day of week (0-7, 0=Sunday)
│ │ │ └─── Month (1-12)
│ │ └───── Day of month (1-31)
│ └─────── Hour (0-23)
└───────── Minute (0-59)
```

**Examples**:
```bash
# Every day at 9am
--schedule "0 9 * * *"

# Every Monday at 2pm
--schedule "0 14 * * 1"

# Every hour
--schedule "0 * * * *"

# Specific date/time (single-run)
--at "2026-02-15 14:30"
```

---

### Remove Job

**Script**: `polycron-remove.sh`

**Syntax**:
```bash
/path/to/polydev/scripts/polycron-remove.sh <job-id>
```

Removes the job from OS scheduler and deletes the job definition file.

---

### List Jobs

**Script**: `polycron-list.sh`

**Syntax**:
```bash
/path/to/polydev/scripts/polycron-list.sh [--all|--enabled|--disabled]
```

**Filters**:
- `--all`: Show all jobs (default)
- `--enabled`: Show only enabled jobs
- `--disabled`: Show only disabled jobs

**Output** (TOON format):
```
jobs{id,schedule,type,enabled,prompt_summary,cwd}:
  daily-report,0 9 * * *,cron,True,Generate daily metrics report...,/home/user/project
  deploy-prod,30 14 15 2 *,once,False,Deploy to production...,/home/user/app
```

---

### View History

**Script**: `polycron-history.sh`

**Syntax**:
```bash
/path/to/polydev/scripts/polycron-history.sh [job-id] [--last N]
```

**Parameters**:
- `job-id`: Optional filter by specific job
- `--last N`: Limit output to last N entries (default: 20)

**Output** (TOON format):
```
history{job_id,triggered_at,pane_id,status}:
  daily-report,2026-02-14T09:00:00Z,5,started
  daily-report,2026-02-13T09:00:00Z,3,started
```

---

## Job Lifecycle

1. **Add**: Job registered to OS scheduler + JSON file created
2. **Trigger**: OS calls `polycron-trigger.sh` at scheduled time
3. **Execute**: Script spawns Claude agent via `spawn-agent.sh`
4. **Log**: Trigger event recorded in `history.jsonl`
5. **Disable** (if `type=once`): Job automatically disabled after execution

---

## Platform Compatibility

| Platform | Scheduler | Notes |
|----------|-----------|-------|
| Linux/macOS | crontab | Full cron syntax support |
| Windows | schtasks | Basic schedule conversion (daily/once) |

**Windows Limitations**:
- Complex cron expressions may not convert perfectly
- Simplified to daily schedules or single-run tasks

---

## Use Cases

### Daily Reports
```bash
/path/to/polydev/scripts/polycron-add.sh daily-metrics \
  --schedule "0 9 * * *" \
  --prompt "Generate daily metrics report from logs" \
  --cwd /home/user/analytics \
  --report /home/user/reports/daily.md
```

### Weekly Cleanup
```bash
/path/to/polydev/scripts/polycron-add.sh weekly-cleanup \
  --schedule "0 2 * * 0" \
  --prompt "Clean up old logs and temporary files" \
  --cwd /home/user/project
```

### One-Time Deployment
```bash
/path/to/polydev/scripts/polycron-add.sh prod-deploy \
  --at "2026-02-15 14:00" \
  --prompt "Deploy version 2.0 to production" \
  --cwd /home/user/app \
  --type once
```

---

## Monitoring

### Check Job Status
```bash
/path/to/polydev/scripts/polycron-list.sh --enabled
```

### View Recent Triggers
```bash
/path/to/polydev/scripts/polycron-history.sh --last 10
```

### Check Specific Job History
```bash
/path/to/polydev/scripts/polycron-history.sh daily-metrics --last 5
```

---

## Troubleshooting

### Job Not Triggering

**Check OS scheduler**:
```bash
# Linux/macOS
crontab -l | grep polycron

# Windows
schtasks /Query /TN "polydev-*"
```

**Check job is enabled**:
```bash
/path/to/polydev/scripts/polycron-list.sh --enabled
```

### View Agent Output

Agent output is saved to the report path specified in the job definition (default: `~/.polydev/cron/reports/<job-id>.md`).

### Manual Trigger (Testing)

```bash
/path/to/polydev/scripts/polycron-trigger.sh <job-id>
```

---

## Security Notes

- Jobs run with the user's permissions
- Prompts are stored in plain text in job JSON files
- Consider file permissions on `~/.polydev/cron/` directory
- OS scheduler runs even when user is not logged in (platform-dependent)

---

## Related Skills

- **spawn-agent**: Used internally to create Claude agents
- **terminal-task-runner**: For interactive background tasks
- **agent-investigator**: For one-off research tasks

