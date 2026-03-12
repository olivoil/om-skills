# Design: Integrate Obsidian CLI & QMD into Skills

**Date**: 2026-03-12
**Status**: Approved

## Context

Two tools are now available that can improve the obsidian skills:

- **Obsidian CLI** (`obsidian`) — vault-native operations: file listing, search, task management, property access, link analysis, note creation. Requires the Obsidian desktop app to be running.
- **QMD** (`qmd`) — hybrid search engine (BM25 + vector + LLM reranking) over the vault's markdown files. Best for semantic/fuzzy matching.

### Tool Selection Principle

- **`qmd`** for semantic/fuzzy search (entity matching, todo completion evidence)
- **`obsidian` CLI** for vault-native operations (file listing, unresolved links, tasks, properties, note creation)
- **`Read`/`Edit`** for complex multi-line edits (insert-at-position, section replacement)

### Limitations Discovered

- `obsidian tasks daily todo` returns nothing — daily note uses dataview queries, not real `- [ ]` lines
- `obsidian tasks done` has no date filter — output must be filtered manually
- `obsidian daily:append` only appends to the end — can't insert at a specific section
- `qmd` needs `qmd update && qmd embed` before queries to catch recent vault changes (~7s)
- CLI write operations are append/prepend only — `Edit` still needed for targeted modifications

## Changes by Skill

### 1. `obsidian-refine-daily-note`

#### Phase 0: Setup
- Replace `echo $OBSIDIAN_VAULT_PATH` with `obsidian vault info=path`
- Replace `Read` daily note with `obsidian daily:read`

#### Phase 1: Discover Vault Entities
- Replace `Glob` across Projects/, Persons/, Topics/, Coding/, Meetings/ with `obsidian files folder=X` for each
- Replace reading each Persons/ file for aliases with `obsidian property:read name=aliases path=Persons/{name}.md` per person
- Add `obsidian tags counts` to build tag catalog

#### Phase 3: Add Missing Wikilinks
- Use `obsidian unresolved` to find broken/missing links instead of manual text scanning against entity catalog
- Use `obsidian links file="{date}"` to see what the daily note already links to (avoid double-linking)

#### Phase 4: Extract Long Sections
- Replace `Write` for new notes with `obsidian create path=... content=...`

#### Phase 4b: Suggest New Entities
- Use `qmd query "{name}"` to check if an entity exists under a different name/spelling before suggesting creation
- Replaces exact-match-only comparison with semantic matching

#### Phase 4c: Suggest Todo Completions
- Use `obsidian tasks todo` to get all open todos from project files (replaces Grep across Projects/)
- Use `qmd query "{todo text}"` to search for completion evidence in today's notes, meetings, coding sessions (replaces keyword grep)

#### Phase 4d: Freeze Done Today
- Use `obsidian tasks done` to find completed tasks, then filter output for target date (replaces Grep for `✅ {date}`)

#### Phase 4e: Move Inline Todos
- No change — `obsidian tasks daily todo` doesn't work with dataview, keep manual scan + Edit

#### Phase 5: Apply & Confirm
- Keep `Edit` for complex multi-line changes

#### Phase 6: Update Project Recent Activity
- Keep `Read`/`Edit` — complex section updates not suited for CLI append

#### allowed-tools
- Add `Bash(obsidian *)` and `Bash(qmd *)`
- Keep `Read, Write, Edit, Glob, Grep` as fallbacks

### 2. `obsidian-session-summary`

#### Step 0: Resolve vault path
- Replace `echo $OBSIDIAN_VAULT_PATH` with `obsidian vault info=path`

#### Step 3: Write session file
- Replace `Write` with `obsidian create path="Coding/..." content="..."`
- Use `obsidian files folder=Coding` to check for existing files (counter logic)

#### Step 4: Link from daily note
- Use `obsidian daily:read` instead of `Read` with path construction
- Keep `Edit` for targeted section insertion (can't use append — needs insert-at-position)

#### allowed-tools
- Add `Bash(obsidian *)`

### 3. `obsidian-weekly-rollup`

#### Phase 1: Setup
- Replace `echo $OBSIDIAN_VAULT_PATH` with `obsidian vault info=path`

#### Phase 2: Collect Data
- Use `obsidian read path="Daily Notes/{date}.md"` for each day
- Use `obsidian links file="{date}"` to get outgoing links, filter for Meetings/ and Coding/ paths (replaces manual wikilink parsing)
- Use `obsidian tasks todo` for all open todos (replaces reading each project's `## Todos` section)
- Use `obsidian tasks done` for completed tasks, filter by date range (replaces Grep across Projects/)

#### Phase 4: Generate Weekly Note
- Replace `Write` with `obsidian create path="Weekly Notes/..." content="..."`

#### allowed-tools
- Add `Bash(obsidian *)`
- Remove `Bash(echo $*)` (no longer needed for vault path)

### 4. `obsidian-transcribe-meeting`

#### Phase 0: Setup
- Replace `echo $OBSIDIAN_VAULT_PATH` with `obsidian vault info=path`

#### Phase 1: Idempotency check
- Replace `grep -rl` with `obsidian search query='recording: "{folder}"' path=Meetings`
- Replace `grep -rl` with `obsidian search query='video_file: "{filename}"' path=Meetings`

#### Phase 3: Create meeting note
- Replace `Write` with `obsidian create path="Meetings/..." content="..."`

#### Phase 3.5: Extract Key Screenshots — EXPANDED
Current: "Only applies when a video recording exists"
New: applies to **all recording modes**

Split into two steps:
1. **Find user screenshots** — runs for ALL modes (including rodecaster-only):
   ```bash
   bash skills/transcribe-meeting/scripts/find-screenshots.sh "{date}" "{start_time}" "{duration_secs}"
   ```
   Copy found screenshots to vault Attachments and embed at corresponding transcript positions. `find-screenshots.sh` has no video dependency — it just matches screenshot timestamps against the meeting time window.

2. **Supplement with ffmpeg-extracted frames** — only when video exists (omarchy+rodecaster or omarchy-only):
   - If fewer than 3 user screenshots found, extract frames from video at key transcript moments
   - If 3+ user screenshots found, skip ffmpeg extraction
   - If no video file exists (rodecaster-only), skip this step entirely

#### Phase 5: Link from daily note
- Use `obsidian daily:read` + `Edit` for targeted insertion

#### Phase 6: Link from project note
- Use `obsidian append path="Projects/{project}.md" content="- [[{date} {Title}]]"` when a `## Meetings` section already exists
- Keep `Read`/`Edit` when the section needs to be created

#### allowed-tools
- Add `Bash(obsidian *)`

## Not Changed

- **`github-pr-review`** — not an obsidian skill, no integration needed
- **`intervals-time-entry`** — browser automation skill, vault interaction is minimal (just writes back to daily note via Edit)
- **`intervals-to-freshbooks`** — API + browser skill, no vault interaction
