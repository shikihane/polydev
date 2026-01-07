---
name: polydev-brainstorm
description: |
  Decompose complex/greenfield work into parallel tasks. MUST use for new projects before parallelizing.
  TRIGGERS: new project, from scratch, greenfield, complex task, multiple features, decompose, brainstorm
---

# Polydev Brainstorm

Turn ideas into well-defined parallel tasks through collaborative dialogue.

---

## ⚠️ GREENFIELD PROJECT - SKELETON FIRST

```
┌─────────────────────────────────────────────────────────────────┐
│ FOR NEW PROJECTS (no existing code):                            │
│                                                                 │
│ 1. Identify SKELETON work (must be done FIRST, single-threaded) │
│ 2. Skeleton = project structure, core interfaces, shared types  │
│ 3. Only AFTER skeleton is merged can you parallelize            │
│                                                                 │
│ WHY: Parallel branches on empty repo = merge hell + conflicts   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Your Task

Help the user decompose their work into parallel-friendly tasks.

## Process

### Phase 1: Understand Context

**Check project first:**
- Scan project structure (files, docs, recent commits)
- Identify project type (Node.js, Python, Rust, etc.)
- Detect available infrastructure (test frameworks, etc.)
- **CRITICAL: Is this a NEW/empty project?** → Skeleton first!

**Ask questions one at a time:**
- Prefer multiple choice questions
- Only one question per message
- Focus on: purpose, constraints, success criteria, dependencies

### Phase 2: Identify Skeleton (for greenfield)

**If project is NEW, identify skeleton work:**

| Skeleton Component | Example |
|-------------------|---------|
| Project structure | directories, config files |
| Core interfaces | shared types, base classes |
| Build system | package.json, Cargo.toml, etc. |
| Shared utilities | common helpers, constants |

**Skeleton MUST be completed single-threaded before any parallel work.**

### Phase 3: Explore Approaches

**Propose 2-3 approaches with trade-offs:**
- Lead with recommended option and reasoning
- Consider parallelization potential
- Identify task dependencies

### Phase 4: Decompose Tasks

**Break work into parallel-friendly tasks:**

| Task | Branch | Dependencies | Verification Level |
|------|--------|--------------|-------------------|
| **Skeleton** | skeleton/base | None | L1 |
| Auth API | feature/auth | Skeleton | L3 |
| User Profile | feature/profile | Auth API | L2 |

**Verification Levels:**
- L0: Skip (docs, config)
- L1: Compile only
- L2: Unit tests
- L3: Integration tests
- L4: E2E tests
- L5: Manual verification

### Phase 5: Present Design

**Present in sections (200-300 words each):**
1. Architecture overview
2. **Skeleton scope** (if greenfield)
3. Task breakdown with dependencies
4. Verification strategy

**After each section:** "Does this look right so far?"

---

## Output Format

When design is complete, output:

```markdown
## Skeleton (if greenfield)

Must complete FIRST before parallelizing:
- [ ] Project structure
- [ ] Core interfaces
- [ ] Build configuration

## Parallel Tasks (after skeleton)

| Task | Branch | Plan File | Verification |
|------|--------|-----------|--------------|
| Auth | feature/auth | plans/auth.md | L3 |
| Profile | feature/profile | plans/profile.md | L2 |

## Dependencies
- feature/profile depends on feature/auth (UserService)

## Execution Order
1. Complete skeleton (single-threaded)
2. Start auth + dashboard in parallel
3. Start profile after auth completes
```

---

## Next Steps

After brainstorming, offer:

```
Design complete. Options:

1. **Build Skeleton First** (if greenfield)
   → I'll implement the skeleton single-threaded, then we parallelize

2. **Write Plans** - Create detailed implementation plans
   → Use polydev-plans skill for each task

3. **Direct Execution** - Start parallel development now
   → Use polydev skill (only if skeleton exists!)

Which approach?
```

---

## Key Principles

- **Skeleton first** - New projects need foundation before parallelizing
- **One question at a time** - Don't overwhelm
- **YAGNI ruthlessly** - Remove unnecessary features
- **Parallelization focus** - Design for concurrent execution
- **Verification-aware** - Consider testability from start
