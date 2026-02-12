# Service Inventory

> Updated by the orchestrator after each work unit commit.
> Coder agents MUST read this before implementing to avoid duplicating existing services.

## Services

| Service | File | Responsibility | Key Methods |
|---------|------|---------------|-------------|
| _Example: TodoService_ | _src/server/services/todo.ts_ | _CRUD operations for todos_ | _create, update, delete, getAll_ |

## Factories

| Factory | File | Creates | Used By |
|---------|------|---------|---------|
| _Example: createApp()_ | _src/server/index.ts_ | _Express app with middleware_ | _server startup, tests_ |

## Database Tables

| Table | Schema File | Query Layer | Service |
|-------|------------|-------------|---------|
| _Example: todos_ | _src/server/db/schema.ts_ | _src/server/db/queries.ts_ | _TodoService_ |

## Shared Modules

| Module | File | Exports | Used By |
|--------|------|---------|---------|
| _Example: validation_ | _src/shared/validation.ts_ | _Zod schemas_ | _routes, WebSocket handler_ |

## Established Patterns

<!-- Document patterns discovered during implementation so later work units follow them -->

- _Example: Factory pattern for testable Express servers (createApp() returns app without listening)_
- _Example: In-memory SQLite (`:memory:`) for tests_
- _Example: Zod for input validation at API boundaries_
