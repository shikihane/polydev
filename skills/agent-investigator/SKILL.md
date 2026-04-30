---
name: agent-investigator
description: "Use when a spawned read-only investigation agent must analyze code or docs, write a report, and emit an AGENT_DONE marker"
---

# Agent Investigator

This skill is for read-only investigation sessions started by a Polydev adapter. It is provider-neutral: Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, or another coding agent may run it.

## Context

Do not call Polydev orchestration scripts. Your responsibilities are:

1. Understand the startup prompt.
2. Search, read, and analyze code or documentation.
3. Write the requested report file.
4. Emit the completion marker.

The main agent detects completion from terminal output and reads the report.

## Completion Marker

When done, output exactly:

```text
[AGENT_DONE]
report: <full path to report file>
timestamp: <ISO timestamp>
summary: <summary in 20 words or less>
```

## Report Template

```markdown
# Investigation Report: <Topic>

Generated: <ISO timestamp>

## Summary

<3-5 sentences with the decision-relevant findings.>

## Findings

### 1. <Finding>

<Evidence and explanation.>

## Key Files

| File | Lines | Description |
| --- | --- | --- |
| `path/to/file` | 10-30 | Why it matters |

## Recommendations

1. **<Action>** - <Reason>
```

## Rules

- Keep terminal output concise.
- Put details in the report, not the terminal.
- Do not modify code unless the startup prompt explicitly changes the role.
- Do not wait for user input.
- Do not omit `[AGENT_DONE]`.
