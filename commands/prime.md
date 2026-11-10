---
description: Load relevant knowledge base facts into context before starting work
---

# Prime (metaswarm knowledge priming)

**CRITICAL**: Run this command at the START of any investigation, planning, or implementation work to load relevant knowledge into your context.

## When to Use

- Starting work on a GitHub Issue
- Beginning investigation/research
- Before writing a plan
- Before implementing changes
- When switching to a new area of the codebase

## How It Works

`/prime` reads metaswarm's knowledge base, the JSONL fact files in `.beads/knowledge/` (the project's own learnings) and, in the metaswarm repo, the shipped examples in `knowledge/`, and filters it with `jq` down to the facts relevant to your current work, so you:

1. Follow established patterns and rules
2. Avoid known gotchas and pitfalls
3. Make decisions aligned with architectural choices
4. Don't repeat mistakes that have been learned from

`/prime` filters on three things, any combination of which can be given as arguments (e.g. `/prime auth src/api/auth/ implementation`):

| Filter | Matches against |
|---|---|
| **Keyword** (topic, e.g. `auth`) | `.fact` and `.tags` (case-insensitive) |
| **File** (path or path fragment you will touch) | `.affectedFiles` |
| **Work type** (planning, implementation, review, debugging, research, release) | `.type` (e.g. `gotcha`, `pattern`, `decision`, `api_behavior`) |

The bd workflow reference is separate: if bd is installed, plain `bd prime` prints bd's own workflow reference and any `bd remember` memories. It has no filters and never reads `.beads/knowledge/`, so use `/prime` for the knowledge base.

## Usage

The knowledge files may start with `#` comment lines (the shipped `knowledge/*.jsonl` do), so strip them with `grep -hv '^#'` before handing the lines to `jq`. Set `KB` to the store you want to search:

```bash
KB=.beads/knowledge      # project knowledge (or: KB=knowledge for the shipped examples)
```

### Prime for Keywords

When working on a specific topic (`K` is a case-insensitive regex):

```bash
K="auth"
grep -hv '^#' "$KB"/*.jsonl | jq -r --arg k "$K" 'select((.fact | test($k; "i")) or ((.tags // []) | any(test($k; "i")))) | .fact + (if .recommendation then "\n  -> " + .recommendation else "" end)'
```

### Prime for Files

When working on specific files (`F` is a path or path fragment):

```bash
F="src/api/auth/"
grep -hv '^#' "$KB"/*.jsonl | jq -r --arg f "$F" 'select((.affectedFiles // []) | any(contains($f))) | .fact + (if .recommendation then "\n  -> " + .recommendation else "" end)'
```

### Prime for Work Type

Pick the fact types that matter for the work you are doing:

| Work type | Fact types to load |
|---|---|
| planning | `decision`, `pattern`, `gotcha`, `dependency`, `security` |
| implementation | `pattern`, `gotcha`, `api_behavior`, `dependency`, `performance`, `security` |
| review | `pattern`, `gotcha`, `decision`, `security`, `performance` |
| debugging | `gotcha`, `api_behavior`, `code_quirk`, `dependency`, `performance` |
| research | `decision`, `pattern`, `gotcha`, `api_behavior`, `code_quirk`, `dependency`, `performance`, `security` (all types) |
| release | `decision`, `pattern`, `gotcha`, `dependency`, `security` |

```bash
T="pattern|gotcha|api_behavior|dependency|performance|security"   # implementation
grep -hv '^#' "$KB"/*.jsonl | jq -r --arg t "$T" 'select(.type | test("^(" + $t + ")$")) | "[\(.type)] " + .fact + (if .recommendation then "\n  -> " + .recommendation else "" end)'
```

### Combined

Filters compose with `and` inside one `select`:

```bash
grep -hv '^#' "$KB"/*.jsonl | jq -r --arg k "auth" --arg f "src/api/" --arg t "gotcha|pattern" '
  select(((.fact | test($k; "i")) or ((.tags // []) | any(test($k; "i"))))
         and ((.affectedFiles // []) | any(contains($f)))
         and (.type | test("^(" + $t + ")$")))
  | "[\(.type)] \(.fact) -> \(.recommendation // "")"'
```

### Prime for Context Recovery

When resuming after context compaction or in a new session, see "Context Recovery" below: read the persisted plan and context files directly, then prime for the work you are resuming.

## What Gets Loaded

### 1. MUST FOLLOW (Critical Rules)

Non-negotiable rules containing NEVER/ALWAYS/MUST:

- "NEVER use `as any` type casting"
- "ALWAYS use centralized AI config"
- Security-critical patterns

### 2. GOTCHAS (Common Pitfalls)

Known issues to avoid:

- "Truthy check fails for explicit zero values - use !== undefined"
- API behavior quirks

### 3. PATTERNS (Best Practices)

Established patterns in this codebase:

- "Use mock factories from test utilities"
- "Services should follow TDD (Red-Green-Refactor)"

### 4. DECISIONS (Architectural Choices)

Team/architectural decisions:

- "State management uses Zustand + TanStack Query"
- "AI providers implement Strategy Pattern"

### 5. API BEHAVIORS

External API quirks:

- "Prisma findMany returns [] not null"

## Integration Points

### In Planning Phase

Before writing a plan, run `/prime` for planning work on the task's keywords.

### In Implementation Phase

Before writing code, run `/prime` for implementation work touching the files you will change.

### In Review Phase

Before reviewing code, run `/prime` for review work touching the changed files.

## Manual Knowledge Check

If you need to check for specific knowledge:

```bash
# Search for a specific topic
grep -hv '^#' .beads/knowledge/*.jsonl | jq -r 'select(.fact | test("authentication"; "i")) | .fact'

# Get all gotchas
grep -hv '^#' .beads/knowledge/gotchas.jsonl | jq -r '.fact'

# Get all patterns
grep -hv '^#' .beads/knowledge/patterns.jsonl | jq -r '.fact'
```

## Output Format

Present the filtered facts grouped like this:

```markdown
# Relevant Knowledge Base Facts

_25 facts loaded for this context_

## MUST FOLLOW (Critical Rules)

These are non-negotiable rules:

- **[pattern]** NEVER use `as any` type casting...
- **[security]** Always validate JWT tokens server-side...

## GOTCHAS (Common Pitfalls)

Avoid these known issues:

- **[gotcha]** Truthy check fails for explicit zero values...

## PATTERNS (Best Practices)

- **[pattern]** Use mock factories from test utilities...
```

## Context Recovery

When an orchestrator detects it lost context (after compaction or in a new session), recover in this order: if bd is installed, `bd prime` (bd context); then read `.beads/plans/active-plan.md` and `.beads/context/*.md`; then `/prime` for knowledge. Also check `.beads/context/review-history/` for a non-closed file: it is an interrupted review gate. Resume it at its next round, and if its `status` is `clarify-pending`, re-ask the pending questions instead of iterating.

### What Gets Read

1. **Active Plan**: `.beads/plans/active-plan.md`, resumed only if it has `status: in-progress`
2. **Project Context**: `.beads/context/project-context.md` (completed work units, established patterns, tooling)
3. **Execution State**: `.beads/context/execution-state.md` (current work unit, phase, VALIDATE attempts, review round)
4. **Review History**: any non-closed `.beads/context/review-history/*.json` (an interrupted gate; `clarify-pending` means re-ask the pending questions, do not iterate)
5. **Standard Knowledge**: the MUST FOLLOW, GOTCHAS, PATTERNS and DECISIONS facts that `/prime` filters for the resumed work

### Recovery Flow

```bash
# 1. Check for active execution
if [ -f .beads/plans/active-plan.md ]; then
  grep -q 'status: in-progress' .beads/plans/active-plan.md && echo "ACTIVE PLAN FOUND"
fi

# 2. Read all context files
cat .beads/plans/active-plan.md           # The approved plan
cat .beads/context/project-context.md     # Completed work, patterns
cat .beads/context/execution-state.md     # Where we left off

# 3. Load knowledge base facts for the resumed work: set T to the resumed
#    work type's fact types (see the work-type table above); recommendations included
T="pattern|gotcha|api_behavior|dependency|performance|security"   # e.g. resuming implementation
grep -hv '^#' .beads/knowledge/*.jsonl | jq -r --arg t "$T" 'select(.type | test("^(" + $t + ")$")) | "[\(.type)] " + .fact + (if .recommendation then "\n  -> " + .recommendation else "" end)'
```

### When Recovery Triggers

- Orchestrated execution starts and finds `.beads/plans/active-plan.md` with `status: in-progress` but has no plan in its current context
- A new session starts while `.beads/context/execution-state.md` shows work in progress
- After context compaction, when the agent recognizes it has lost plan/execution context

### Output Format (Recovery Mode)

```markdown
# Context Recovery

_Recovered from persisted state in .beads/_

## Active Plan
<plan summary — title, work unit count, current position>

## Execution State
- Current work unit: WU-<id> (<title>)
- Phase: <IMPLEMENT|VALIDATE|REVIEW|COMMIT>
- Completed: <N> of <total> work units

## Project Context
<tooling, completed work units, established patterns>

## Relevant Knowledge
<standard priming output: MUST FOLLOW, GOTCHAS, PATTERNS, DECISIONS>
```

## Verification

After priming, you should be able to answer:

1. What are the critical rules I must follow?
2. What gotchas should I watch out for?
3. What patterns should I apply?
4. What architectural decisions constrain my options?
5. (If recovering) Where did execution stop and what comes next?
