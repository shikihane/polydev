# Verification Levels

## Overview

Each task in a parallel implementation plan must specify a verification level. This ensures consistent quality gates across all branches.

## Verification Level Definitions

| Level | Name | Verification Scope | Use Case |
|-------|------|-------------------|----------|
| L0 | skip | No verification | Docs, comments, config changes |
| L1 | compile | Build only | Minor changes, formatting, refactoring |
| L2 | unit | Build + unit tests | Regular features, utilities |
| L3 | integration | + integration tests | Module interaction, API endpoints |
| L4 | e2e | + end-to-end tests | Core user flows, critical paths |
| L5 | manual | + human verification | Cannot automate, security-critical |

## Verification Commands Format

Every plan should specify verification commands:

```markdown
**Verification Commands:**
- Build: `npm run build`
- Test: `npm test`
- Lint: `npm run lint`
```

## Verification Checklist Template

```markdown
## Verification Checklist

- [ ] All tests pass: `npm test`
- [ ] Build succeeds: `npm run build`
- [ ] Lint passes: `npm run lint`
- [ ] Manual verification (if L5): [specific steps]
```

## Rollback Plan

Include rollback instructions for verification failures:

```markdown
## Rollback Plan

If verification fails:
1. `git stash` current changes
2. Review failing tests
3. Fix or escalate to architect
```

## Default Workflow by Level

| Level | Workflow |
|-------|----------|
| L0 | Commit directly |
| L1 | Build → Commit |
| L2 | Build → Unit Tests → Commit |
| L3 | Build → Unit Tests → Integration Tests → Commit |
| L4 | Build → Unit Tests → Integration Tests → E2E Tests → Commit |
| L5 | Build → Tests → Code Review → Human Approval → Commit |
