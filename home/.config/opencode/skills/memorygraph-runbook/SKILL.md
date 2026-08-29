---
name: memorygraph-runbook
description: Operational CLI runbook for memorygraph (FalkorDB-backed graph memory). Use when about to invoke any `memorygraph <subcommand>` directly — memory CRUD (store/get/update/delete/search/recall/related/link), temporal (as-of/history/changes), context search (context-search/contextual-search), analytics & intelligence (stats/activity/visualize/similarity/learning/gaps/entities/patterns/context), proactive (briefing/predict/warn/outcome), integration (capture/analyze-project/workflow), or data management (export/import/migrate/health/config) — and need the exact flags, defaults, exit-code behavior, or the 35 relationship types. SKIP for general recall (use the honcho skill or ctx_search); this is for direct CLI invocations and recipe authoring.
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  workflow: operational
  failure_mode: documented
argument-hint: "[subcommand: store|get|update|delete|search|recall|related|link|...]"
---

# memorygraph-runbook

Operational reference for the `memorygraph` CLI (v0.13.0, FalkorDB-backed). The
single source of truth for how to invoke each subcommand, what defaults to
expect, and where the live traps are. AGENTS.md owns the routing policy
(memorygraph vs ctx_search); this skill owns the operational mechanics.

## What I do

- Document every `memorygraph <subcommand>` with required args, optional
  flags, defaults (in **bold**), example invocation, output format, and the
  gotchas that have actually bitten operators in production.
- Encode the full 35-relationship-type and 13-memory-type enums from
  `~/source/memory-graph/ts/src/models.ts` so you do not have to grep the
  source.
- Enforce the corrected REPLACES recipe (DEC-055/DEC-056) so supersession
  consolidations do not fabricate edges via the multi-hop `related` query.
- Carry the four-state FalkorDB-down doctrine (DEC-013) and the 6 known
  FalkorDB v4.16.3 parser bugs (ERR-003) so the dialect traps stop
  recurring.

## When to use me

**Use when:**

- You are about to invoke any `memorygraph <subcommand>` and need the exact
  flag, default, or output format
- You are authoring a recipe or runbook that calls memorygraph and want
  the canonical reference for the subcommand shape
- You are debugging a memorygraph invocation that returned surprising
  output (empty result, wrong-tag recall, malformed edge)
- You need to confirm a relationship type or memory type before
  `memorygraph link` / `memorygraph store`
- You need to know whether a failure is a known parser bug (ERR-003 family)
  or something new

**Skip when:**

- You need general semantic recall across past sessions → use the `honcho`
  skill or `ctx_search` (BM25/BM25-ish session memory). Routing predicate in
  AGENTS.md: identifier/tag queries → memorygraph; prose queries →
  ctx_search.
- You need to discover *what* happened in a past session → `ctx_search` first,
  then memorygraph for the curated DEC-NNN/ERR-NNN nodes.
- You are authoring a new skill, not invoking memorygraph itself.

## Backend matrix

Five backends are supported; the active one is selected via `MEMORY_BACKEND`
or `--backend <type>`. Production uses **memgraph** (bolt-shared) against
**Neo4j 5.26 Community on the VPS** (DEC-048, since 2026-08-24). The local
FalkorDB container is decommissioned (volume preserved for rollback until
2026-08-27; archived compose at `infra/falkordb-archive/` in desktop-link).

| Backend        | Use case                          | Active?         | Env vars                                                  |
|----------------|-----------------------------------|-----------------|-----------------------------------------------------------|
| `falkordblite` | Single-process local (default)    | dev only        | `MEMORY_FALKORDBLITE_PATH=~/.memorygraph/falkordblite.db`  |
| `sqlite`       | Legacy archive (read-only)        | no (DEC-001)    | `MEMORY_SQLITE_PATH=~/.memorygraph/memory.db`             |
| `falkordb`     | Decommissioned local Docker       | no (DEC-048; rollback only until 2026-08-27) | `MEMORY_BACKEND=falkordb`, `MEMORY_FALKORDB_HOST=localhost`, `MEMORY_FALKORDB_PORT=6379` |
| `memgraph`     | **Production** — bolt-shared vs Neo4j VPS `bolt://100.99.168.33:7687` (container `neo4j-prod-shadow`, Tailscale-only) | **YES** | `MEMORY_BACKEND=memgraph`, `MEMORY_MEMGRAPH_URI`, `MEMORY_MEMGRAPH_USER`, `MEMORY_MEMGRAPH_PASSWORD` (also in `~/.memorygraph/neo4j.env`) |
| `neo4j`        | NOT implemented in the fork (factory throws) | no      | —                                                          |
| `cloud`        | MemoryGraph Cloud (managed)       | no              | `MEMORYGRAPH_API_KEY`, `MEMORYGRAPH_API_URL`               |

Infrastructure for the active backend: compose `infra/neo4j-shadow/` in the
desktop-link repo deployed on the VPS (`neo4j:5.26-community`, APOC, caps
1536M, bind `100.99.168.33` only). Pre-flight: Tailscale up + container
running. Latency reference: TCP p50 ~136 ms / p95 ~141 ms.

To confirm which backend is live:

```bash
memorygraph config
#   Backend: memgraph
#   Tool Profile: core
```

## Global options

Apply to every subcommand:

- `--backend <type>` — override `MEMORY_BACKEND` for one invocation.
  Backends: `falkordblite | sqlite | falkordb | memgraph | cloud`.
- `--profile <type>` — tool profile (`core` default, `extended`). Legacy
  aliases `lite→core`, `standard→extended`, `full→extended`.
- `--help`, `-h` — print full USAGE block to stdout, exit 0.
- `--version`, `-v` — print `memorygraph <version>` to stdout, exit 0.

No args at all → prints USAGE block to stdout, exit 0.
Unknown subcommand → prints USAGE to stdout **and** stderr
`Unknown command: <name>`, exit 1.

## Memory operations

### store

Create a new memory node.

- **Required:** `--type <type>`, `--title <title>`, `--content <content>`
- **Optional:** `--tags <csv>` (comma-separated, parsed by `parseList`),
  `--importance <0..1>` (**default 0.5**), `--summary <text>`
- **Example:**
  ```bash
  memorygraph store \
    --type solution \
    --title "DEC-NNN: <one-line description>" \
    --content "..." \
    --tags <project-slug> \
    --importance 0.8
  ```
- **Output:** `Stored memory: <uuid> (<type>)` on success. Errors (missing
  required, validation) on stderr, exit 1.
- **Gotchas:**
  - `--tags` is **single-substring tokenized**, NOT a comma-separated AND
    list (desktop-link napkin #8 / DEC-013 P0). Use one tag per call and
    filter by title.
  - `--type` must be one of the 13 memory types; mistyped type fails
    validation server-side with `Error: Invalid memory type: <value>`.
  - `--importance` is parsed by `parseFloatArg`; non-numeric silently
    becomes `0.5`.

### get

Fetch a memory by UUID.

- **Required:** positional `<memory-id>`
- **Optional:** none
- **Example:**
  ```bash
  memorygraph get <uuid>
  ```
- **Output:** formatted markdown block with type/title/content/tags/edges.
- **Gotchas:** UUIDs are stored as `id` attribute; copy them verbatim from
  `store` output or `search --limit 1` results.

### update

Patch an existing memory.

- **Required:** positional `<memory-id>`
- **Optional:** `--title`, `--content`, `--summary`, `--tags <csv>`,
  `--importance <0..1>`. Only supplied flags are updated.
- **Example:**
  ```bash
  memorygraph update <uuid> --importance 0.9 --tags <project-slug>
  ```
- **Gotchas:** `--tags` REPLACES the tag set, it does not append. Use
  `store` of a new memory if you want to preserve history.

### delete

Remove a memory. Alias: `rm`.

- **Required:** positional `<memory-id>`
- **Optional:** none
- **Gotchas:** delete is hard-delete by default; relationships referencing
  the deleted node are also removed (FalkorDB `DETACH DELETE` semantics).

### search

Token/substring recall with tag and type filters.

- **Optional:** `--query <text>` (substring, not semantic),
  `--tags <csv>` (single-tag recommended; see napkin #8),
  `--types <csv>` (memory types, e.g. `solution,error`),
  `--project <path>`, `--min-importance <0..1>`, `--limit <1..1000>`
  (**default 50**, clamped), `--offset <int>` (**default 0**),
  `--tolerance <strict|normal|fuzzy>` (**default normal**),
  `--match-mode <any|all>` (**default any**)
- **Example:**
  ```bash
  memorygraph search --tags <project-slug> --limit 10
  ```
- **Output:** markdown list of memory summaries up to `--limit`. Empty
  results: `Found 0 memories for search query` — exit **0** (NOT a
  failure; see "Assert content, not exit codes" in AGENTS.md).
- **Gotchas:**
  - Search is **token/substring match**, not semantic — `related`/
    `recall` are the fuzzy alternatives. `--query "authentication
    security"` matches the literal substring.
  - `--tags <a>,<b>` is OR, not AND — pass **one** tag per call.
  - Default `--limit` is 50, NOT 10. Add `--limit 10` explicitly to
    reduce recall noise.

### recall

Fuzzy natural-language search (lighter than `search`).

- **Required:** `--query <text>` OR positional query
- **Optional:** `--types <csv>`, `--project <path>`, `--limit <int>`
  (**default 20**), `--offset <int>` (**default 0**)
- **Example:**
  ```bash
  memorygraph recall --query "authentication security" --limit 5
  ```
- **Gotchas:** still token/substring; do not expect LLM embeddings. If you
  need true semantic recall, fall back to `ctx_search` or the `honcho` skill.

### related

Traverse the relationship graph from a seed memory.

- **Required:** positional `<memory-id>`
- **Optional:** `--types <csv>` (filter by relationship type),
  `--max-depth <int>` (**default 2** — multi-hop!)
- **Example:**
  ```bash
  memorygraph related <uuid> --types SOLVES,CAUSES --max-depth 1
  ```
- **Output:** markdown list of related memories with their relationship
  edge and strength.
- **Gotchas (P0):**
  - `--max-depth` default is **2**, not 1. The 1-hop seed's direct edges
    are returned alongside 2-hop neighbours, conflating them.
    **This is the DEC-055/DEC-056 P0 defect** — the napkin #34
    REPLACES recipe was wrong because `memorygraph related` is multi-hop.
    For a true 1-hop direct-edge query, use direct Cypher (see REPLACES
    recipe below) or `--max-depth 1` (which works for the enum-filtered
    case but may trigger FalkorDB dialect failure on some types — see
    ERR-003 below).
  - `--max-depth 1` with `--types <unknown-type>` can exit 0 with empty
    output and a stderr dialect error (ERR-003 family). Assert on
    content, not exit code.

### link

Create a relationship edge between two memories.

- **Required:** positional `<from-uuid> <to-uuid> <TYPE>`
- **Optional:** `--strength <0..1>` (**default 0.5**), `--confidence
  <0..1>` (**default 0.8**), `--context <text>`
- **Example:**
  ```bash
  memorygraph link <from-uuid> <to-uuid> REPLACES \
    --strength 0.9 --confidence 0.8 --context "DEC-NNN supersedes prior"
  ```
- **Output:** confirmation line; non-zero exit on invalid type.
- **Gotchas (P0):**
  - The relationship type MUST be one of the 35 enums below. Typos
    (any string not in the enum, e.g. a present-tense form instead of
    the past-tense `RELATED_TO`) fail with `Failed to create
    relationship: Error: Invalid relationship type: <your-typo>` and
    exit 1.
  - The CLI default is `strength=0.5, confidence=0.8`. Recipe authors
    who need a "strong" edge MUST pass `--strength 0.9` explicitly —
    DEC-055 P0 defect: prior recipe taught `--strength 0.9` but the
    default was used because the flag was not passed.

## Temporal

### as-of

Query relationships as of a specific timestamp (point-in-time graph).

- **Required:** positional `<memory-id> <iso-timestamp>`
- **Optional:** `--types <csv>`
- **Example:**
  ```bash
  memorygraph as-of <uuid> 2026-08-01T00:00:00Z --types SOLVES,REPLACES
  ```
- **Gotchas:**
  - As-of may emit a confusing two-line response: `Found 1 related
    memories for <uuid>` followed by `No relationships found for memory
    '<uuid>' as of <ts>`. The edge exists; the timestamp filter does
    not match the edge's `valid_from`. Verify with `memorygraph history
    <uuid>` instead. (Verified 2026-08-11 — empty result, exit 0; this
    is the documented "assert content, not exit code" pattern.)

### history

List all historical edges for a memory (lifecycle of an edge over time).

- **Required:** positional `<memory-id>`
- **Optional:** `--types <csv>`
- **Example:**
  ```bash
  memorygraph history <uuid> --types REPLACES
  ```
- **Use:** primary verification tool after `link`/`memorygraph related`
  shows nothing — `history` does NOT depend on the multi-hop traversal
  and reveals edges that were created/updated/deleted over time.

### changes

Show all relationship changes since a timestamp.

- **Required:** positional `<iso-timestamp>`
- **Example:**
  ```bash
  memorygraph changes 2026-08-10T00:00:00Z
  ```

## Context search

### context-search

Search edges by context criteria (combined type + strength + query filter).

- **Required:** positional `<memory-id>`
- **Optional:** `--types <csv>`, `--min-strength <0..1>`,
  `--context-query <text>`, `--limit <int>` (**default 20**)
- **Example:**
  ```bash
  memorygraph context-search <uuid> --types REPLACES --min-strength 0.8 \
    --context-query "supersession"
  ```

### contextual-search

Search within the context of a memory's related items (recursive).

- **Required:** positional `<memory-id>` OR `--memory-id <uuid>`, plus
  `--query <text>` (or empty for traversal-only)
- **Optional:** `--max-depth <int>` (**default 2**)
- **Gotchas:** subject to the same multi-hop conflation as `related` —
  prefer `context-search` when you need an explicit type/strength filter.

## Analytics

### stats

Get database statistics (memory count, relationship count, type breakdown).

- **Required:** none
- **Output:** markdown stats block.

### activity

Recent activity summary.

- **Optional:** `--days <int>` (**default 7**), `--project <path>`
- **Output:** markdown block of recent stores/links.

### visualize

Graph visualization data (nodes + edges for a center, up to N hops).

- **Optional:** `--center <memory-id>` (default: all), `--depth <int>`
  (**default 2**), `--max-nodes <int>` (**default 100**), `--json`
- **Output:** markdown summary plus `--json` dump.

### similarity

Find similar solutions to a given memory.

- **Required:** positional `<memory-id>`
- **Optional:** `--top-k <int>` (**default 5**), `--min-similarity <0..1>`
  (**default 0.3**)

### learning

Recommend learning paths for a topic.

- **Optional:** `--topic <text>` OR positional (**default "general"**),
  `--max-paths <int>` (**default 3**)

### gaps

Identify knowledge gaps in a project.

- **Optional:** `--project <path>`

### entities

Extract named entities from a memory's content.

- **Required:** positional `<memory-id>`
- **Optional:** `--link` (write extracted entities as graph nodes)

### patterns

Find similar problems and suggest patterns.

- **Required:** `--query <problem description>` OR positional

### context

Intelligent context retrieval for a query or project (combined relevance
ranking, entities, token estimate).

- **Optional:** `--query <text>`, `--project <path>`. Empty query → empty
  result. Token budget: **4000** (hardcoded in `getContext` call).

## Proactive

### briefing

Generate a session briefing for the cwd project.

- **Optional:** `--path <dir>` (**default cwd**), `--verbosity
  <minimal|standard|detailed>` (**default standard**)

### predict

Predict what memories might be needed next.

- **Optional:** `--query <text>` (defaults to all candidates)

### warn

Warn about potential issues relevant to the current context.

- **Optional:** `--context <text>`

### outcome

Record an outcome for a memory (used by outcome-learning).

- **Required:** positional `<memory-id>`, `--description <text>`,
  `--success <true|false>`

## Integration

### capture

Capture the current task context (writes a `task` memory node).

- **Optional:** `--task <text>` OR positional, `--goals <csv>`

### analyze-project

Analyze the cwd project (detected type + codebase summary).

- **Optional:** `--path <dir>` (**default cwd**)

### workflow

Track or suggest workflow improvements.

- **Optional:** `--action <track|suggest>` (**default suggest**),
  `--task <text>`, `--type <text>`, `--data <text>`, `--session <id>`

## Data management

### export

Export memories to JSON or Markdown.

- **Required:** `--format <json|markdown>`, `--output <path>`
- **Output (JSON):** stats to stderr (`Export complete!`, count + path)
- **Output (Markdown):** writes one file per memory to `<output>/`

### import

Import memories from JSON (idempotent with `--skip-duplicates`).

- **Required:** `--input <json-file>`
- **Optional:** `--skip-duplicates`

### migrate

Migrate memories between backends. **Use with care.**

- **Required:** `--to <backend>` (`sqlite | falkordblite | cloud |
  falkordb`)
- **Optional:** `--to-path <path>`, `--to-uri <uri>`, `--dry-run`,
  `--no-verify`
- **Gotchas:** dry-run prints `Dry-run successful - migration would
  proceed safely` and exits 0 without writing. Real runs print
  verification stats to stderr.

### health

Run a health check (connectivity + stats).

- **Optional:** `--json` (JSON output), `--timeout <seconds>`
  (**default 5.0**)
- **Output (text):** status block to stderr (`Status: Healthy/Unhealthy`,
  backend type, connected flag, statistics, timestamp)
- **Output (JSON):** full structured object to stdout
- **Exit codes:** **0** if status="healthy", **1** if "unhealthy"
- **Gotchas:** exit 0 does NOT prove schema/index correctness — only
  connectivity. Run `memorygraph store --type general --title "test"…
  --content x --tags healthcheck` + `memorygraph search --tags
  healthcheck` for a true write/read round-trip.

### config

Print current configuration summary to stderr (no flags, exits 0).

## Relationship types (35, grouped)

From `~/source/memory-graph/ts/src/models.ts:38-81`. Grouped by intent
(comments in source). Use these EXACTLY as the third positional arg to
`memorygraph link <from> <to> <TYPE>` — typos are hard errors.

### Causal (5)

| Type        | Meaning                                         |
|-------------|-------------------------------------------------|
| `CAUSES`    | A causes B                                      |
| `TRIGGERS`  | A triggers B (weaker than CAUSES)               |
| `LEADS_TO`  | A leads to B (causal chain)                     |
| `PREVENTS`  | A prevents B                                    |
| `BREAKS`    | A breaks B (negation of ENSURES/REQUIRES)       |

### Solution (5)

| Type             | Meaning                                          |
|------------------|--------------------------------------------------|
| `SOLVES`         | A solves B (a problem → a fix)                   |
| `ADDRESSES`      | A addresses B (weaker than SOLVES)               |
| `ALTERNATIVE_TO` | A is an alternative to B                         |
| `IMPROVES`       | A improves on B                                  |
| `REPLACES`       | **A supersedes B** — the canonical supersession edge. See REPLACES recipe below. **Always pass `--strength 0.9 --confidence 0.8` explicitly.** |

### Context (5)

| Type         | Meaning                                          |
|--------------|--------------------------------------------------|
| `OCCURS_IN`  | A occurs in B context                            |
| `APPLIES_TO` | A applies to B domain                            |
| `WORKS_WITH` | A works with B                                   |
| `REQUIRES`   | A requires B                                     |
| `USED_IN`    | A is used in B (workflow)                        |

### Learning (5)

| Type            | Meaning                                        |
|-----------------|------------------------------------------------|
| `BUILDS_ON`     | A builds on B                                  |
| `CONTRADICTS`   | A contradicts B                                |
| `CONFIRMS`      | A confirms B                                   |
| `GENERALIZES`   | A generalizes B                                |
| `SPECIALIZES`   | A specializes B                                |

### Similarity (5)

| Type           | Meaning                                          |
|----------------|--------------------------------------------------|
| `SIMILAR_TO`   | A is similar to B                                |
| `VARIANT_OF`   | A is a variant of B                              |
| `RELATED_TO`   | **A is related to B (default generic)**          |
| `ANALOGY_TO`   | A is an analogy for B                            |
| `OPPOSITE_OF`  | A is the opposite of B                           |

### Workflow (5)

| Type          | Meaning                                          |
|---------------|--------------------------------------------------|
| `FOLLOWS`     | A follows B (sequence)                           |
| `DEPENDS_ON`  | A depends on B                                   |
| `ENABLES`     | A enables B                                      |
| `BLOCKS`      | A blocks B                                       |
| `PARALLEL_TO` | A is parallel to B                               |

### Quality (5)

| Type              | Meaning                                       |
|-------------------|-----------------------------------------------|
| `EFFECTIVE_FOR`   | A is effective for B                          |
| `INEFFECTIVE_FOR` | A is ineffective for B                        |
| `PREFERRED_OVER`  | A is preferred over B                         |
| `DEPRECATED_BY`   | A is deprecated by B                          |
| `VALIDATED_BY`    | A is validated by B (evidence-backed)         |

Total: 35. **Typo trap:** any past-tense variation not in the enum above
rejected — for example, the **present-tense** form of the generic
relationship fails. The correct generic is `RELATED_TO` (past tense).
Such typos fail with `Invalid relationship type: <your-typo>` and exit
1.

## Memory types (13)

From `~/source/memory-graph/ts/src/models.ts:14-28`. Required by
`memorygraph store --type <type>`. Mistyped types fail validation.

| Type             | Live use | Meaning                                       |
|------------------|----------|-----------------------------------------------|
| `task`           | rare     | A task node (used by `capture`)               |
| `code_pattern`   | rare     | A reusable code pattern                       |
| `problem`        | rare     | A problem statement                           |
| `solution`       | **heavy**| **The canonical DEC-NNN/ERR-NNN node type**   |
| `project`        | rare     | Project metadata                              |
| `technology`     | rare     | Tech/library entry                            |
| `error`          | medium   | An error pattern                              |
| `fix`            | rare     | A fix recipe (mostly superseded by `solution`)|
| `command`        | rare     | A command recipe                              |
| `file_context`   | rare     | File-level context                            |
| `workflow`       | rare     | Workflow capture                              |
| `general`        | medium   | Generic notes                                 |
| `conversation`   | rare     | Conversation fragment                         |

**Empirical note:** of 337 memories currently in the graph, **~95%**
are `type=solution` (DEC-NNN, ERR-NNN, recipes). The other 12 types are
defined in the enum but rarely produced. Prefer `solution` unless the
recipe explicitly calls for a different type.

## Output format conventions

- **stdout:** the canonical human-readable or JSON output. Pipe-friendly
  for `--json` modes.
- **stderr:** all progress, status, config, and warning lines. **Many
  `memorygraph <subcmd>` invocations emit results to stderr** —
  `eprint()` is used throughout `cli.ts`. If you need to capture
  output, redirect both: `memorygraph search --tags foo 2>&1 | ...`.
- **JSON:** only emitted on explicit `--json` flag (search does not
  have `--json`; `health` and `visualize` do).
- **Errors:** `Error: <message>` to stderr, **exit 1**. Unknown
  subcommand → exit 1 + USAGE block to stdout.

## Exit code behavior

Verified empirically (per the FalkorDB dialect-failure table in the
desktop-link napkin #4 / ERR-003):

| Exit | When                                                    | Example                                              |
|------|---------------------------------------------------------|------------------------------------------------------|
| **0**| Success                                                 | `memorygraph store …` on valid input                 |
| **1**| Unknown subcommand                                      | `memorygraph foo`                                    |
| **1**| Missing required arg                                    | `memorygraph store` (no `--type`)                    |
| **1**| Invalid enum value                                      | `memorygraph link a b NOT_IN_ENUM`                   |
| **1**| Validation / server error                               | `memorygraph get <bad-uuid>`                         |
| **0**| **Dialect failure with empty output** (ERR-003)         | `memorygraph related <id> --types BAD_TYPE --max-depth 1` — error on stderr, **stdout empty, exit 0**. Always assert on content, not exit code. |
| **0**| Empty result                                            | `memorygraph search --tags nonexistent --limit 5`    |
| **0**| `health` healthy                                        | `memorygraph health`                                 |
| **1**| `health` unhealthy                                      | FalkorDB down + `memorygraph health`                 |

## Do / Don't

Distilled from the corpus (DEC/ERR + per-project napkins). Citations
inline.

### DO

1. **DO use `--tags <project-slug>` (single tag, per call)** — substring
   tokenizer at `cli.ts:432`. Pair with title-prefix parsing
   (`DEC-NNN`, `ERR-NNN`) for type filtering. See napkin #8.
2. **DO pass `--strength 0.9 --confidence 0.8` explicitly on `link`**
   when you need a "strong" edge. The CLI defaults are 0.5 / 0.8
   (`cli.ts:632-633`) — DEC-055 P0 was caused by relying on the
   default.
3. **DO use direct Cypher enumeration when consolidating via
   `REPLACES`** — see recipe below. Never use `memorygraph related`
   for the enumeration step (multi-hop, DEC-056 P0).
4. **DO use `memorygraph history <id> --types <TYPE>` to verify edges
   landed** — history does not depend on multi-hop traversal and
   reveals edge lifecycle.
5. **DO assert on content, not exit code** for `related` /
   `recall` / `search` — ERR-003 dialect failures exit 0 with empty
   stdout.
6. **DO use `memorygraph as-of <id> <iso>` for point-in-time
   reconstruction** — preferred over `related` for temporal debugging.
7. **DO batch a single tag per call** when filtering by project;
   combine with subsequent title-filter to narrow further.

### DON'T

1. **DON'T use `--tags <a>,<b>` expecting AND-match.** The tokenizer
   OR-matches tag tokens — `--tags desktop-link,decision` returns any
   memory tagged either substring. (Desktop-link napkin #8, P0;
   fabricated DEC-055 BLOCKS edges traced to this bug.)
2. **DON'T use bare `memorygraph related <id>` for 1-hop enumeration.**
   Default `--max-depth 2` conflates direct edges with 2-hop
   neighbours. (DEC-055/DEC-056 P0; release-notes-analyzer napkin #34.)
3. **DON'T pass any string not in the 35-type enum** as the
   relationship type. The CLI rejects with `Invalid relationship type`
   and exit 1. The correct generic is `RELATED_TO` (past tense).
4. **DON'T trust exit 0 as proof of success.** FalkorDB dialect
   failures (see ERR-003 bugs below) exit 0 with empty stdout. Always
   inspect content. (Desktop-link napkin #4 / ERR-003.)
5. **DON'T call `memorygraph related <id> --types <unknown-type>
   --max-depth 1` and assume the empty result means "no such edge".**
   The combination can trigger a dialect failure that exits 0 with an
   empty list. Fall back to direct Cypher or `history`.
6. **DON'T run `memorygraph migrate --to falkordb` against the live
   graph without `--dry-run` first.** Dry-run prints `Dry-run
   successful` and exits without writing; skips the verification
   round-trip.
7. **DON'T stop the live FalkorDB container to test "FalkorDB down"
   behavior.** It is shared with desktop-link / release-notes-analyzer
   / meetings-mcp opencode sessions; stopping it triggers Honcho
   FAIL-CLOSED across all of them. Run a dedicated test container on
   port 6380 instead (`MEMORY_FALKORDB_PORT=6380 docker compose …`).
8. **DON'T assume `--limit` defaults to 10.** `search` defaults to
   **50** (`cli.ts:551`), `recall` to **20**, `learning` to **3**
   (`max-paths`). Add `--limit` explicitly when you need a tighter
   recall window.

## Failure mode (DEC-013 four-state matrix)

When memorygraph is the source of truth and FalkorDB is the backend, the
following doctrine applies (carried verbatim from
`docs/context/hybrid-recall-policy.md`):

| FalkorDB | context-mode (`ctx_search`) | Action                                                                  |
|----------|------------------------------|-------------------------------------------------------------------------|
| up       | up                           | **Normal operation.** `memorygraph search --tags <slug>` for ID/tag queries; `ctx_search` for prose. |
| down     | up                           | **Degrade to `ctx_search` + file layers.** Report the graph skipped. `resume` doctrine — non-critical flows do NOT hard-stop. |
| up       | down                         | **Use memorygraph for ID/tag queries;** session memory unavailable for prose. Continue with `--tags <slug>` only. |
| down     | down                         | **File layers only + clear double-fail message.** Never a silent partial. |

Hard-stop triggers (fail-closed):

- `@escriba finalize` with FalkorDB down → **fail-fast** (finalize
  cannot persist).
- `honcho` recall on a non-trivial task with FalkorDB down → **STOP
  and surface** (FAIL-CLOSED doctrine in `~/.config/opencode/AGENTS.md`).

## REPLACES recipe (corrected, DEC-056)

The P0 napkin defect (DEC-055 / DEC-056) taught operators to use
`memorygraph related` for the enumeration step. **Do not.** The
`related` subcommand is multi-hop (default `--max-depth 2`) and
conflates direct edges with 2-hop neighbours. The corrected recipe
uses direct Cypher to enumerate the OLD node's outbound edges, then
re-emits each from the AUTHORITATIVE-NEWER node.

```bash
# Step 0: identify the authoritative-newer uuid and the superseded-older uuid.
#   The authoritative-newer is the curated DEC/ERR node you just stored.
#   The superseded-older is the prior version it replaces.

# Step 1: emit the REPLACES edge with explicit strength=0.9 + confidence=0.8 + context
memorygraph link <authoritative-newer-uuid> <superseded-older-uuid> REPLACES \
  --strength 0.9 --confidence 0.8 --context "DEC-NNN supersedes the prior version"

# Step 2: enumerate the OLD node's outbound edges via direct Cypher.
#   This is the key fix — `memorygraph related` is multi-hop and will
#   return fabricated neighbours. Direct Cypher gives you the true
#   1-hop outbound set.
#   Linux/macOS (with redis-cli in PATH):
GRAPH.QUERY memorygraph "MATCH (s {id: '<superseded-older-uuid>'})-[r]->(m) RETURN type(r), r.strength, m.id, m.title"
#   Windows (redis-cli not in PATH) — use docker exec into the FalkorDB container:
docker exec memorygraph-falkordb redis-cli GRAPH.QUERY memorygraph "MATCH (s {id: '<superseded-older-uuid>'})-[r]->(m) RETURN type(r), r.strength, m.id, m.title"

# Step 3: for each (type, m.id) returned, re-emit from AUTHORITATIVE-NEWER
#   with the original strength (use 0.9 if missing — the CLI default 0.5
#   silently weakens the edge).
memorygraph link <authoritative-newer-uuid> <m.id> <type> \
  --strength <r.strength> --context "REPLACES consolidation"

# Step 4: verify each edge landed at the prescribed strength via history.
#   history does NOT use multi-hop traversal — it walks the edge lifecycle.
memorygraph history <authoritative-newer-uuid> --types <type>
```

**Why not `memorygraph related <superseded-older-uuid>` in Step 2?**

- Default `--max-depth` is **2**, so a 1-hop seed returns both direct
  edges AND 2-hop neighbours. The 2-hop noise gets re-emitted as
  if it were a direct edge → fabricated REPLACES consolidation.
- Even with `--max-depth 1`, the combination with some enum filters
  triggers a FalkorDB dialect failure (ERR-003 family) that exits
  **0** with empty stdout. The defect then hides silently.

**Why `memorygraph history` in Step 4 instead of `memorygraph
related`?** `history` walks the edge creation/update/delete timeline
of a single memory, so the multi-hop conflation does not apply. It is
the canonical verification tool after `link`.

## Cross-references

- **Canonical CLI source:** `~/source/memory-graph/ts/src/cli.ts` (1403
  lines, v0.13.0). Update this runbook when the source changes.
- **Type enums:** `~/source/memory-graph/ts/src/models.ts:14-28` (13
  memory types) + `~/source/memory-graph/ts/src/models.ts:38-81` (35
  relationship types).
- **Empirical base (DEC/ERR):** `~/.config/opencode/context/INDEX.jsonl`
  (one JSON object per line per repo; resolve via `index-md read --slug <slug>`);
  see `docs/context/inbox/INDEX-schema.md` for the schema and `index-md self-test` for the round-trip assertion.
  Historical decision IDs in the empirical base: DEC-001–055, ERR-001–018.
- **Empirical base (napkins):**
  - `desktop-link/.claude/napkin.md` — Shell & Command Reliability
    #1 (FalkorDB Docker), #4 (parser bugs), #8 (tag AND-bug), #10
    (AGENTS.md override)
  - `release-notes-analyzer/.claude/napkin.md` — #34 (P0 REPLACES
    recipe defect, keystone)
  - `~/.claude/napkin.md` — global cross-workspace notes
- **Hybrid recall policy (authoritative):**
  `desktop-link/docs/context/hybrid-recall-policy.md` (four-state
  matrix origin).
- **Docker compose:** `~/source/memorygraph-docker/docker-compose.yml`.
- **Companion skill:** `~/.config/opencode/skills/honcho/SKILL.md`
  (recall + dual-write trigger; this runbook is the operational
  complement).

## Closing the loop

After successful work, persist the recipe or decision:

```bash
memorygraph store --type solution --tags <project-slug> \
  --title "DEC-NNN: <one-line description>" \
  --content "<what worked, what didn't, how to apply next time>" \
  --importance 0.8
```

For supersession, emit a `REPLACES` edge to the prior version using
the corrected recipe above. Always confirm `memorygraph history
<new-uuid> --types REPLACES` returns the edge with `strength: 0.9`.