---
description: Decompose complex work into parallel tasks with verification strategy
argument-hint: [task description or leave empty for interactive mode]
---

# Polydev Brainstorm

Turn ideas into well-defined parallel tasks through collaborative dialogue.

## Your Task

Help the user decompose their work into parallel-friendly tasks.

## Process

### Phase 1: Understand Context

**Check project first:**
- Scan project structure (files, docs, recent commits)
- Identify project type (Node.js, Python, Rust, etc.)
- Detect available infrastructure (test frameworks, MCP servers)

**Ask questions one at a time:**
- Prefer multiple choice questions
- Only one question per message
- Focus on: purpose, constraints, success criteria, dependencies

### Phase 2: Explore Approaches

**Propose 2-3 approaches with trade-offs:**
- Lead with recommended option and reasoning
- Consider parallelization potential
- Identify task dependencies

### Phase 3: Decompose Tasks

**Break work into parallel-friendly tasks:**

| Task | Branch | Dependencies | Verification Level |
|------|--------|--------------|-------------------|
| Auth API | feature/auth | None | L3 |
| User Profile | feature/profile | Auth API | L2 |

**Verification Levels:**
- L0: Skip (docs, config)
- L1: Compile only
- L2: Unit tests
- L3: Integration tests
- L4: E2E tests
- L5: Manual verification

### Phase 4: Present Design

**Present in sections (200-300 words each):**
1. Architecture overview
2. Task breakdown with dependencies
3. Verification strategy

**After each section:** "Does this look right so far?"

## Output Format

When design is complete, output:

```markdown
## Parallel Tasks

| Task | Branch | Plan File | Verification |
|------|--------|-----------|--------------|
| Auth | feature/auth | plans/auth.md | L3 |
| Profile | feature/profile | plans/profile.md | L2 |

## Dependencies
- feature/profile depends on feature/auth (UserService)

## Execution Order
1. Start auth + dashboard in parallel
2. Start profile after auth completes
```

## Next Steps

<CRITICAL>
When the user makes a choice, you MUST immediately load the top-level `polydev` skill and use the matching internal reference:
- User chooses "Write Plans" -> `references/writing-plans.md`
- User chooses "Direct Execution" -> `references/worktree-executor.md`

DO NOT just describe what to do. Continue with the selected Polydev reference immediately.
</CRITICAL>


After brainstorming, offer:

```
Design complete. Options:

1. **Write Plans** - Create detailed implementation plans
   -> Use `polydev` with `references/writing-plans.md`

2. **Direct Execution** - Start parallel development now
   -> Use `polydev` with `references/worktree-executor.md`

Which approach?
```

## Key Principles

- **One question at a time** - Don't overwhelm
- **YAGNI ruthlessly** - Remove unnecessary features
- **Parallelization focus** - Design for concurrent execution
- **Verification-aware** - Consider testability from start
