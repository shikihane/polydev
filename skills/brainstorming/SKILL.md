---
name: brainstorming
description: "Use before parallel development - explores requirements, decomposes tasks, and designs verification strategy through collaborative dialogue."
---

# Brainstorming for Parallel Development

## Overview

Turn user ideas into well-defined parallel tasks through collaborative dialogue. This is the **prerequisite** for using polydev's parallel execution.

**Announce at start:** "I'm using the brainstorming skill to understand and decompose this work."

## The Process

### Phase 1: Understanding the Idea

**Check project context first:**
- Scan project structure (files, docs, recent commits)
- Identify project type (Node.js, Python, Rust, etc.)
- Detect available infrastructure (test frameworks, MCP servers)

**Ask questions one at a time:**
- Prefer multiple choice questions when possible
- Only one question per message
- Focus on: purpose, constraints, success criteria, dependencies

### Phase 2: Exploring Approaches

**Propose 2-3 approaches with trade-offs:**
- Lead with recommended option and reasoning
- Consider parallelization potential
- Identify task dependencies

**Example:**
```
Approach A (Recommended): Feature branches with shared utils
- Pro: Maximum parallelism, clear ownership
- Con: Potential merge conflicts in shared code

Approach B: Sequential with shared state
- Pro: No conflicts
- Con: Slower, blocking dependencies
```

### Phase 3: Task Decomposition

**Break work into parallel-friendly tasks:**

| Task | Branch | Dependencies | Verification Level |
|------|--------|--------------|-------------------|
| Auth API | feature/auth | None | L3 |
| User Profile | feature/profile | Auth API | L2 |
| Dashboard | feature/dashboard | None | L4 |

**Verification Levels:**
- L0: Skip (docs, config)
- L1: Compile only
- L2: Unit tests
- L3: Integration tests
- L4: E2E tests
- L5: Manual verification

### Phase 4: Presenting the Design

**Present in sections (200-300 words each):**
1. Architecture overview
2. Task breakdown with dependencies
3. Verification strategy
4. Risk assessment

**After each section:** "Does this look right so far?"

## After the Design

**Documentation:**
- Write design to `docs/plans/YYYY-MM-DD-<topic>-design.md`
- Include task dependency graph
- Document verification commands

**Ready for Implementation:**
```
Design complete. Options:

1. **Write Plans** - Create detailed implementation plans for each task
   → Use polydev:writing-plans skill

2. **Direct Execution** - Start parallel development immediately
   → Use polydev:polydev skill

Which approach?
```

## Key Principles

- **One question at a time** - Don't overwhelm
- **Multiple choice preferred** - Easier to answer
- **YAGNI ruthlessly** - Remove unnecessary features
- **Parallelization focus** - Design for concurrent execution
- **Verification-aware** - Consider testability from the start
- **Dependency minimization** - Reduce task coupling

## Integration with Polydev

This skill feeds directly into polydev's workflow:

```
brainstorming
    ↓
writing-plans (optional, for complex tasks)
    ↓
polydev:polydev (parallel execution)
    ↓
worktree-executor (per-branch execution)
```

**Handoff format:**
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
