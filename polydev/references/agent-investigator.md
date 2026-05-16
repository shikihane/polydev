# Agent Investigator

This reference is for read-only investigation sessions started by a Polydev adapter. Investigation panes are provider-neutral and pane-oriented: Codex CLI, Cursor, OpenCode, Claude Code, Gemini CLI, or another coding agent may run in the terminal.

## Contract

Investigation sessions do not use `task.toon` and do not use a completion marker. They are visible terminal panes. The coordinator observes them with `--peek`, `capture-screen.sh`, or direct terminal inspection.

The investigation agent should:

1. Understand the prompt sent into the pane.
2. Search, read, and analyze code or documentation as requested.
3. Keep terminal output concise enough for capture.
4. Stop issuing commands when finished and leave the pane idle.

If the prompt asks for a report file, write that file. If it does not, answer in the pane.

## Coordinator Flow

```bash
"/c/Users/<user>/.claude/skills/polydev/scripts/spawn-agent.sh" research --cwd /path/to/project
"/c/Users/<user>/.claude/skills/polydev/scripts/send-prompt.sh" <pane_id> --file /tmp/research-prompt.md --peek 5
"/c/Users/<user>/.claude/skills/polydev/scripts/capture-screen.sh" --pane-id <pane_id> --lines 80
```

Do not use a blocking wait helper as the default status path. If the coordinator needs status, capture the pane and judge the visible terminal state.

## Rules

- Do not require a Git worktree.
- Do not require `task.toon`.
- Do not require completion markers.
- Do not modify code unless the prompt explicitly changes the role.
- Do not wait for user input unless the prompt explicitly asks for a human decision.
