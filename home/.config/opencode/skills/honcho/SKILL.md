---
name: honcho
description: Recall prior decisions, errors, and plans from Honcho + memory-graph (FalkorDB) before starting non-trivial work. Use when choosing between alternative implementations, debugging a recurring issue, or when the user says "like last time", "remember", or refers to past work. SKIP for trivial tasks (read-only exploration, single-file syntax lookups) or when the user tags `@honcho skip` / `/skip-honcho`. FAIL-CLOSED: if FalkorDB @ localhost:6379 is unreachable and the task is non-trivial, stop and surface to the user.
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  workflow: recall
  failure_mode: fail-closed
---

## What I do
- Query Honcho for prior decisions and errors related to the current project
- Search memory-graph (FalkorDB @ localhost:6379) for adjacent context
- Surface stored solutions before re-deriving

## When to use me
Use at the start of any non-trivial task:
- Before editing configs, migrations, schemas, CI, infra
- Before choosing between alternative implementations or libraries
- When debugging a recurring issue
- When the user mentions "like last time", "remember", or refers to past work

Skip this skill entirely for trivial tasks: read-only exploration, single-file
syntax lookups (use context7 instead), one-line edits with no behavioral
change, or tasks the user tagged as throwaway/`/skip-honcho`.

## Native Honcho tools (MCP)
These are exposed by the Honcho MCP server and preferred over the CLI when
available — they handle peer/session mapping and result shaping automatically:
- `honcho_status()` — confirm Honcho is reachable and show workspace mapping
- `honcho_get_config(field?)` — read effective peer/session config (omit field for full dump)
- `honcho_search(query, max_items?)` — top prior decisions/errors for the query
- `honcho_chat(query)` — reasoning-backed answer scoped to current peer
- `honcho_create_conclusion(content)` — persist durable memory at session end
- `honcho_set_config(field, value, confirm?)` — persist a setting
- `honcho_setup(apiKey?, baseUrl?, peerName?, persistGlobal?)` — bootstrap Honcho for a project

## memory-graph CLI (Bash)
Use when you need tag-filtered recall or temporal state:
```
memorygraph search --tags <project>
memorygraph related <id>
memorygraph as-of <timestamp>
memorygraph history
```

## Failure mode (FAIL-CLOSED for non-trivial tasks)
FalkorDB stack: `falkordb/falkordb:v4.16.3` on `localhost:6379`.
Compose at `~/source/memorygraph-docker/docker-compose.yml`.
Env: `MEMORY_BACKEND=falkordb`, `MEMORY_FALKORDB_HOST=localhost`,
`MEMORY_FALKORDB_PORT=6379`.

If the backend is unreachable (docker compose down, port closed, network
error) and the task is non-trivial → STOP and surface to the user:
1. (a) `docker compose up -d` in `~/source/memorygraph-docker/`, then retry
2. (b) confirm with `@honcho skip` to proceed without recall (trivial only)
3. (c) abort the task

Never auto-skip. Never retry indefinitely. One warn, then stop.

## Search semantics
Memory-graph search is a token/substring matcher, NOT semantic. For reliable
recall, prefer `--tags <project>` over free-text `--query`.

## Closing the loop
After successful work, persist with one or both of:
```
memorygraph store --type solution --tags <project> --title "DEC-NNN: ..."
honcho_create_conclusion --content "..."
```
