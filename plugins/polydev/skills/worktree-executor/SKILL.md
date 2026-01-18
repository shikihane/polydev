---
name: worktree-executor
description: SUB-AGENT ONLY: This skill should be used when spawned in isolated worktree - executes PLAN.md and syncs status to task.toon.
version: 0.1.0
---

# Worktree Executor

Execute implementation plans in isolated worktrees with mandatory status synchronization.

**Announce at start:** "I'm executing the plan in this worktree."

---

## Important: Sub-Agent Context

This is a sub-agent started by the main agent via `spawn-session.sh`, running in an isolated worktree.

**Do NOT call any polydev scripts.** The responsibilities are:
1. Read `PLAN.md`
2. Execute tasks step by step
3. Update `task.toon` status
4. Commit code changes

The main agent monitors `task.toon` status via `poll.sh`.

---

## Iron Law - Violation = Failure

Every status change MUST be **immediately** written to task.toon:

| Event | task.toon fields |
|-------|------------------|
| Start executing | overall_status: in_progress |
| Need orchestration help | overall_status: blocked, blocking_reason: <why> |
| Must have human decision | overall_status: hil, blocking_reason: <why> |
| Batch done, waiting for review | overall_status: hil, blocking_reason: Awaiting code review |
| All tasks complete | overall_status: completed |

---

## Execution Flow

### Step 1: Initialize

1. Update task.toon -> `overall_status: in_progress`, clear `blocking_reason`
2. Read `PLAN.md` from worktree root
3. Review critically - identify any questions or concerns
4. If concerns: Update task.toon -> `hil`, set `blocking_reason`, STOP
5. If no concerns: Create TodoWrite and proceed

### Step 2: Execute Batch

**Default batch size: 3 tasks**

For each task in batch:

1. Mark task as `in_progress` in TodoWrite
2. Follow each step exactly as written in plan
3. Run verification commands as specified
4. If step fails:
   - Analyze the failure
   - If fixable: fix and retry
   - If blocked: go to Step 4
5. Mark task as `completed` in TodoWrite
6. Commit changes (if plan specifies)

### Step 3: Report & Checkpoint

When batch complete:

```
Batch [N] complete:
- Task 1: [description] done
- Task 2: [description] done
- Task 3: [description] done

Verification output:
[test/build output]

Update task.toon -> hil, blocking_reason: Awaiting code review
```

**STOP and wait for feedback.**

### Step 4: Handle Blockers

**blocked vs hil - Critical Distinction:**

| Status | Who solves | Examples |
|--------|-----------|----------|
| **blocked** | main agent / other agents | depends on another branch, system bug, env issue |
| **hil** | human only | design decisions, credentials, security, ambiguous requirements |

**blocked flow:**
1. Determine main agent might be able to solve
2. Update task.toon:
   ```
   overall_status: blocked
   blocking_reason: Needs UserService from feature/auth branch, not yet complete
   ```
3. **STOP** - do not retry, wait for main agent

**hil flow:**
1. Determine human intervention required
2. Update task.toon:
   ```
   overall_status: hil
   blocking_reason: Unclear if user wants OAuth or JWT
   ```
3. **STOP** - wait for human decision

### Step 5: Continue After Feedback

Based on feedback:
1. Update task.toon -> `in_progress`, clear `blocking_reason`
2. Apply requested changes if any
3. Execute next batch
4. Repeat until complete

### Step 6: Complete

When all tasks done:
1. Run final verification (all tests, build, lint)
2. **Commit all changes (MANDATORY):**
   ```bash
   git add -A
   git diff --cached --quiet || git commit -m "feat(<branch-name>): implementation complete"
   ```
   **Never skip this step** - uncommitted changes will be lost when worktree is removed.
3. Update task.toon -> `overall_status: completed`
4. Output completion summary

---

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Hit a blocker mid-batch (missing dependency, test fails repeatedly)
- Plan has critical gaps preventing progress
- You don't understand an instruction
- Verification fails and you can't fix it

**Ask for clarification rather than guessing.**

---

## Critical Reminders

- If you pause but don't update task.toon, the workflow **deadlocks**!
- ALWAYS set `blocking_reason` - main agent needs it to decide how to handle
- The main agent monitors you **only** through task.toon
- When blocked: STOP immediately, don't retry endlessly
- Follow plan steps **exactly** - don't improvise
- Don't skip verifications

---

## Rule Reflection (Check Before Completion)

**Trigger conditions** (all must be met):
1. Encountered **environment/compatibility/parameter usage** issue
2. Issue **will recur when new Agent executes**
3. Issue **has been solved** with a clear solution

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
