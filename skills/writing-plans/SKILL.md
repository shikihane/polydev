---
name: writing-plans
description: "Use when creating detailed implementation plans for polydev parallel tasks - generates step-by-step PLAN.md files"
---

# Writing Implementation Plans

## Overview

Write comprehensive implementation plans with bite-sized tasks. Plans should be self-contained - assume the executor has zero context about the codebase.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md` or `PLAN.md` in worktree root.

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For Claude:** Execute this plan task-by-task using polydev:worktree-executor skill.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Verification Level:** [L0-L5]

**Verification Commands:**
- Build: `npm run build`
- Test: `npm test`
- Lint: `npm run lint`

---
```

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**

```markdown
### Task 1: [Component Name]

**Files:**
- Create: `src/auth/jwt.ts`
- Modify: `src/middleware/index.ts:45-60`
- Test: `tests/auth/jwt.test.ts`

**Step 1: Write the failing test**

```typescript
describe('JWT Auth', () => {
  it('should validate token', () => {
    const result = validateToken('valid-token');
    expect(result.valid).toBe(true);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test -- --grep "JWT Auth"`
Expected: FAIL with "validateToken is not defined"

**Step 3: Write minimal implementation**

```typescript
export function validateToken(token: string): { valid: boolean } {
  // Implementation here
  return { valid: true };
}
```

**Step 4: Run test to verify it passes**

Run: `npm test -- --grep "JWT Auth"`
Expected: PASS

**Step 5: Commit**

```bash
git add src/auth/jwt.ts tests/auth/jwt.test.ts
git commit -m "feat(auth): add JWT validation"
```
```

## Task Dependencies

**Mark dependencies explicitly:**

```markdown
### Task 2: User Profile API

**Depends on:** Task 1 (JWT Auth)

**Reason:** Needs validateToken() for authentication middleware
```

## Plan Principles

- **Exact file paths always** - No ambiguity
- **Complete code in plan** - Not "add validation here"
- **Exact commands with expected output** - Verifiable
- **DRY, YAGNI, TDD** - Keep it minimal
- **Frequent commits** - One per task or sub-task

## Verification Section

**End every plan with:**

```markdown
## Verification Checklist

- [ ] All tests pass: `npm test`
- [ ] Build succeeds: `npm run build`
- [ ] Lint passes: `npm run lint`
- [ ] Manual verification (if L5): [specific steps]

## Rollback Plan

If verification fails:
1. `git stash` current changes
2. Review failing tests
3. Fix or escalate to architect
```

## Execution Handoff

After saving the plan:

```
Plan complete and saved to `docs/plans/<filename>.md`.

**Execution options:**

1. **Parallel Development** - Use polydev:polydev to execute in isolated worktree
   - Best for: Large features, multiple related tasks

2. **Direct Execution** - Execute in current session
   - Best for: Small fixes, single-file changes

Which approach?
```

## Integration with Polydev

When used with polydev parallel execution:

1. Plan is copied to worktree as `PLAN.md`
2. worktree-executor reads and executes the plan
3. Status updates written to `task.toon`
4. Main agent monitors via poll.sh (using `$POLYDEV_SCRIPTS/poll.sh`)

**Plan location in worktree:**
```
.worktrees/feature-auth/
├── PLAN.md          # This plan
├── task.toon        # Execution status
└── src/             # Working code
```

## Execution via Polydev

**Main agent spawns worktree with:**
```bash
POLYDEV_SCRIPTS="/path/to/polydev/scripts"
"$POLYDEV_SCRIPTS/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
```

**Sub-agent (worktree-executor) then:**
1. Reads PLAN.md
2. Executes tasks step-by-step
3. Updates task.toon with status
4. Commits changes as specified in plan
