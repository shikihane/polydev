---
name: agent-investigator
description: "SUB-AGENT ONLY: Use when spawned for read-only research - generates report file and outputs [AGENT_DONE] marker"
---

# Agent Investigator

Execute investigation tasks and generate structured reports.

**Note**: This skill is used by sub-agents, automatically activated when started by `spawn-agent.sh`.

---

## Important: You Are a Sub-Agent

You are a sub-agent started by the main agent via `spawn-agent.sh`.

**You do NOT need to call any polydev scripts.** Your responsibilities are:
1. Understand the investigation task (from startup prompt)
2. Execute investigation (search, read, analyze code/docs)
3. Generate report (write to specified file)
4. Output completion marker (let main agent know you're done)

The main agent detects your `[AGENT_DONE]` output via terminal capture.

---

## Completion Marker Format (Must Follow)

When task is complete, output this **exact format** to terminal:

```
[AGENT_DONE]
report: <full path to report file>
timestamp: <ISO timestamp, e.g., 2025-01-05T10:30:00Z>
summary: <summary in 20 words or less>
```

**Example:**
```
[AGENT_DONE]
report: ./.agent-reports/auth-analysis.md
timestamp: 2025-01-05T10:30:00Z
summary: JWT auth, 3 middlewares, 2 security issues found
```

The main agent detects your completion via `grep "\[AGENT_DONE\]"`.

---

## Report Template

```markdown
# Investigation Report: <Topic>

Generated: <ISO timestamp>

## Summary

<3-5 sentences summarizing key findings - this is what the main agent sees first>

## Findings

### 1. <Finding Title>

<Detailed explanation>

**Key Code:**
```<language>
// path/to/file.ts:123
<relevant code snippet>
```

### 2. <Finding Title>

<Detailed explanation>

## Key Files

| File | Lines | Description |
|------|-------|-------------|
| `src/auth/jwt.ts` | 45-67 | JWT validation logic |
| `src/middleware/auth.ts` | 12-34 | Auth middleware |

## Recommendations

1. **<Recommendation Title>** - <specific action>
2. **<Recommendation Title>** - <specific action>

## Appendix (Optional)

<Additional technical details, code snippets, references>
```

---

## Execution Flow

```
1. Read task description
     |
2. Plan investigation steps
     |
3. Execute investigation (search, read, analyze)
   - Use Glob to find files
   - Use Grep to search patterns
   - Use Read to read code
     |
4. Organize findings, write report
     |
5. Write report to specified file
     |
6. Output [AGENT_DONE] marker
     |
7. Done (main agent reads report)
```

---

## Prohibited Actions

```
DO NOT wait for user input (you're running in background)
DO NOT output lots of process info to terminal (wastes main agent's tokens)
DO NOT forget to output [AGENT_DONE] marker
DO NOT modify code (unless task explicitly requires)
DO NOT call any polydev scripts (you are a sub-agent)

DO keep process info in your head or write to log
DO write final results to report file
DO output only key progress and completion marker to terminal
DO structure report for quick scanning
```

---

## Terminal Output Example

Ideal terminal output should be very concise:

```
Starting investigation: Authentication mechanism analysis

Searching auth-related files...
   Found 12 related files

Analyzing key code...
   - src/auth/jwt.ts
   - src/middleware/auth.ts
   - src/routes/login.ts

Writing report...

Report generated: ./.agent-reports/auth-analysis.md

[AGENT_DONE]
report: ./.agent-reports/auth-analysis.md
timestamp: 2025-01-05T10:30:00Z
summary: JWT auth, 3 middlewares, 2 security issues found
```

---

## Communication with Main Agent

There is no direct communication channel between you and the main agent. The only ways to communicate are:

1. **Report file** - Main agent reads your generated report
2. **[AGENT_DONE] marker** - Main agent detects your completion via terminal output
3. **summary field** - Main agent quickly decides if detailed reading is needed

Keep reports concise and structured so main agent can quickly extract key information.

---

## Rule Reflection (Check Before Completion)

**Trigger conditions** (all must be met):
1. Encountered **environment/compatibility/parameter usage** issue
2. Issue **will recur when new Agent executes**
3. You **have solved it** with a clear solution

**Action:** Write file to `.agent-memory/proposed-rules/<issue-summary>.md`

**Format:**
```markdown
# <Issue Summary>

## Problem
<Describe the issue and trigger conditions>

## Solution
<Specific solution>

## Example
\`\`\`bash
# Wrong approach
...

# Correct approach
...
\`\`\`
```

**Do NOT trigger for:**
- Business logic issues
- One-time issues
- Uncertain if generalizable
