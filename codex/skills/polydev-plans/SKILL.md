---
name: polydev-plans
description: |
  Create detailed implementation plans for polydev parallel tasks.
  WHEN: Before parallel execution, need step-by-step plans, complex features
  WHEN NOT: Simple single-file changes, quick fixes
  TRIGGERS: create plan, implementation plan, write plan, design feature
---

# Writing Implementation Plans

Create comprehensive implementation plans with bite-sized tasks for parallel execution.

**Announce at start:** "I'm creating an implementation plan for this task."

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md` or `PLAN.md` in worktree root.

---

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For Codex:** Execute this plan task-by-task. Read polydev-executor skill for execution protocol.

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

---

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**

```markdown
### Task 1: [Component Name]

**Files:**
- Create: `src/auth/jwt.ts`
- Modify: `src/middleware/index.ts:45-60`
- Test: `tests/auth/jwt.test.ts`

**Step 1: Write the failing test**

\`\`\`typescript
describe('JWT Auth', () => {
  it('should validate token', () => {
    const result = validateToken('valid-token');
    expect(result.valid).toBe(true);
  });
});
\`\`\`

**Step 2: Run test to verify it fails**

Run: `npm test -- --grep "JWT Auth"`
Expected: FAIL with "validateToken is not defined"

**Step 3: Write minimal implementation**

\`\`\`typescript
export function validateToken(token: string): { valid: boolean } {
  // Implementation here
  return { valid: true };
}
\`\`\`

**Step 4: Run test to verify it passes**

Run: `npm test -- --grep "JWT Auth"`
Expected: PASS

**Step 5: Commit**

\`\`\`bash
git add src/auth/jwt.ts tests/auth/jwt.test.ts
git commit -m "feat(auth): add JWT validation"
\`\`\`
```

---

## Task Dependencies

**Mark dependencies explicitly:**

```markdown
### Task 2: User Profile API

**Depends on:** Task 1 (JWT Auth)

**Reason:** Needs validateToken() for authentication middleware
```

---

## Plan Principles

- **Exact file paths always** - No ambiguity
- **Complete code in plan** - Not "add validation here"
- **Exact commands with expected output** - Verifiable
- **DRY, YAGNI, TDD** - Keep it minimal
- **Frequent commits** - One per task or sub-task

---

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

---

## Verification Levels Reference

| Level | Name | Verification Scope | Use Case |
|-------|------|-------------------|----------|
| L0 | skip | None | Docs, config |
| L1 | compile | Build only | Minor changes |
| L2 | unit | Build + unit tests | Features |
| L3 | integration | + integration tests | API endpoints |
| L4 | e2e | + end-to-end tests | User flows |
| L5 | manual | + human verification | Critical features |

---

## Execution Handoff

After saving the plan:

```
Plan complete and saved to `docs/plans/<filename>.md`.

**Execution options:**

1. **Parallel Development** - Execute in isolated worktree via polydev
   - Best for: Large features, multiple related tasks

2. **Direct Execution** - Execute in current session
   - Best for: Small fixes, single-file changes

Which approach?
```

---

## Integration with Polydev

When used with polydev parallel execution:

1. Plan is copied to worktree as `PLAN.md`
2. Spawned Codex instance reads and executes the plan
3. Status updates written to `task.toon`
4. Main Codex monitors via poll.sh

**Plan location in worktree:**
```
.worktrees/feature-auth/
├── PLAN.md          # This plan
├── task.toon        # Execution status
└── src/             # Working code
```

**Spawn command (Windows - MUST use bash):**
```bash
bash "$HOME/.codex/polydev/scripts/spawn-session.sh" <workspace> <branch> <worktree-path> <plan-file>
```
