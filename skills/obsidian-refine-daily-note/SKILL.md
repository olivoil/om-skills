---
name: obsidian-refine-daily-note
description: Improve Obsidian daily notes — polish writing, add missing wikilinks, extract long sections into dedicated notes, suggest new vault entities, and summarize Slack activity. Use when the user types /refine or asks to clean up daily notes.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(obsidian *), Bash(qmd *), ToolSearch
---

# Refine Daily Notes

Improve an Obsidian daily note by polishing prose, adding missing wikilinks to maintain a rich knowledge graph, extracting long sections into dedicated notes, and suggesting new vault entities.

## Auto Mode

When invoked with `--auto` (e.g., `/obsidian-refine-daily-note --auto` or `/obsidian-refine-daily-note 2026-02-14 --auto`), the skill runs fully unattended with no confirmation prompts. This is designed for scheduled/cron execution via `claude -p`.

**In auto mode:**
- **Apply without asking**: Phases 0-3 (setup, entity discovery, slack scan + summary, prose improvements, wikilinks), Phase 4d (freeze "Done today"), and Phase 6 (project recent activity updates)
- **Skip entirely**: Phase 4 (extract long sections), Phase 4b (suggest new entities), Phase 4c (suggest todo completions), Phase 4e (move inline todos) — these require human judgment
- **Phase 1b (Slack)**: Run the scan and write the Slack Activity summary (Phase 1c) directly. Skip the "add time entries?" prompt (step 8-9) — just note uncovered gaps in the Slack Activity section for the user to review later
- **Phase 5**: Skip the confirmation step — apply prose and wikilink changes directly
- **Phase 6**: Apply project recent activity updates directly without confirmation
- **Commit changes**: After all edits are applied, create a git commit with message `vault backup: refine daily note {date}`

**In interactive mode (default):** Behavior is unchanged — all confirmation prompts remain.

## Workflow

### Phase 0: Setup

1. Run `obsidian vault info=path` to get the vault root.
2. Determine the target date: use the argument if provided (e.g., `/obsidian-refine-daily-note 2026-02-14`), otherwise use today.
3. Run `obsidian daily:read` to get today's daily note content. If a different date, use `obsidian read path="Daily Notes/{date}.md"`. Error if missing.

### Phase 1: Discover Vault Entities

Build a catalog of all known entities so you can match them against the daily note text.

1. **Projects**: Run `obsidian files folder=Projects` — extract project names from filenames
2. **People**: Run `obsidian files folder=Persons` to list person files. For each, run `obsidian property:read name=aliases path="Persons/{name}.md"` to get aliases.
3. **Topics**: Run `obsidian files folder=Topics` — extract topic names from filenames
4. **Coding sessions**: Run `obsidian files folder=Coding` — for cross-reference awareness
5. **Meetings**: Run `obsidian files folder=Meetings` — for cross-reference awareness
6. **Tags**: Run `obsidian tags counts` to build a tag catalog

This gives you the full entity catalog to match against the daily note.

### Phase 1b: Slack Activity Scan

**Always run this phase.** If Slack MCP tools are unavailable, skip gracefully with no error.

1. **Load Slack tools**: Use `ToolSearch` to search for `slack` tools. If no Slack MCP tools are available, skip this phase with no error — but always attempt it first.
2. **Search for user's messages** on the target date using `slack_search_public_and_private`:
   - Query: `from:<@U07J89FDWPJ> on:{date}`
3. **Group messages** by channel and 30-minute time windows.
4. **Build a time coverage map** from existing daily note time entries (start times, durations, projects).
5. **Identify gaps**: time windows with 3+ Slack messages but no matching time entry.
6. **Detect huddles**: For each DM or group DM channel found in step 2, read messages around the activity window using `slack_read_channel` with `oldest`/`latest` timestamps. Look for messages from Slackbot containing `"A huddle started"`.
   - Slack's search API does **not** index huddle system messages — they can only be found by reading the channel directly.
   - When a huddle is found, record:
     - **Start time**: the Slackbot message timestamp
     - **Participants**: inferred from the DM/group DM members (the channel context)
     - **Estimated duration**: gap between the huddle start and the next human message in the channel (rough estimate — Slack does not expose huddle duration via API)
   - Huddles should **always** have a corresponding time entry. Flag any huddle that doesn't match an existing entry.
7. **Infer channel→project mapping** from channel names and existing time entries:
   - Check cached mappings in `$VAULT/.claude/intervals-cache/slack-mappings.md`
   - If a new channel→project mapping is discovered, append it to the cache file
8. **Present findings**:
   > Slack activity not covered by time entries:
   > - **#technomic-dev** (2:30-3:15pm, 8 messages): discussed vector search PR issues → [[Technomic]]?
   > - **#exsq-general** (4:00-4:20pm, 4 messages): coordinated with team on AI Upskill → [[EXSQ]]?
   > Add time entries for these?
   >
   > Huddles detected:
   > - **DM with [[Sol Parrot|Sol]]** (12:16pm, ~1h54m): matches `[[EXSQ]] - 1:1 sync with Sol - 2` ✓
   > - **DM with [[Adam Herrneckar|Adam]]** (3:05pm, ~25m): no matching time entry — add one?
9. **If approved**, suggest time entry lines but do **NOT** auto-insert into time entries — present them for the user to manually add (time entries are sacred structured data).

### Phase 1c: Slack Activity Summary

Using the data already gathered in Phase 1b, write a `### Slack Activity` section into the daily note summarizing the day's interactions.

1. **Group by channel/conversation**: For each channel or DM where the user sent messages, build a brief summary:
   - **Channel name** (linked to project if a mapping exists)
   - **Time window** (e.g., 2:30–3:15pm)
   - **Message count**
   - **Topics discussed**: Summarize the key topics, decisions, or questions from the messages (keep to 1–2 sentences per channel). Use context from `slack_read_channel` / `slack_read_thread` if threads were read in Phase 1b, otherwise summarize from search result snippets.
   - **Huddle indicator**: If a huddle was detected in this channel (from Phase 1b step 6), note it with duration.

2. **Format** the section as a bullet list under `### Slack Activity`:
   ```markdown
   ### Slack Activity
   - **#technomic-dev** (2:30–3:15pm, 8 msgs) — Discussed vector search indexing issues; agreed to switch to HNSW. [[Technomic]]
   - **#exsq-general** (4:00–4:20pm, 4 msgs) — Coordinated AI Upskill session logistics with [[Sol Parrot|Sol]]. [[EXSQ]]
   - **DM with [[Adam Herrneckar|Adam]]** (3:05–3:30pm, 3 msgs + huddle ~25m) — Reviewed deployment pipeline changes.
   ```

3. **Wikilink** any people and projects mentioned, using the entity catalog from Phase 1.

4. **Placement**: Insert the section after the time entries block and before the first `### [[Project]]` section (or at the end if no project sections exist). If a `### Slack Activity` section already exists, replace it (idempotent).

5. **Include in Phase 5 preview**: Show the proposed Slack Activity section as part of the change summary for user approval.

If no Slack messages were found in Phase 1b, or Slack MCP tools were unavailable, skip this phase silently.

### Phase 2: Analyze & Improve Writing

Review each section of the daily note:

- **Skip time entries** — the bullet list at the top (lines like `- [[Project]] - task - duration`) is structured data for the intervals skill. Never modify these.
- **Improve prose** — fix grammar, improve clarity, tighten wording. Keep it concise.
- **Fix formatting** — consistent heading levels, list styles, spacing.
- **Preserve todos** — don't reorder, rewrite, or change checkbox state. Only improve prose around them.
- **Author's voice** — improve clarity without rewriting the user's natural style. Don't make it sound like AI wrote it.

### Phase 3: Add Missing Wikilinks

Use vault-native link analysis to find and fix missing wikilinks:

1. Run `obsidian unresolved` to get all unresolved links in the vault — these are references to notes that don't exist yet. Filter for any that appear in today's daily note.
2. Run `obsidian links file="{date}"` to see what the daily note already links to — avoid double-linking.
3. Scan all text (outside time entries) for mentions of known entities from Phase 1 that are not yet linked:

- **Projects**: Add `[[Project Name]]` links where project names appear unlinked
- **People**: Add `[[Full Name]]` or `[[Full Name|Alias]]` when a short name or alias is used
- **Topics**: Add `[[Topic]]` links where topic names appear unlinked
- **Heading style**: Use `### [[Project]]` for project section headings consistently

**Rules:**
- Don't double-link — skip text already inside `[[...]]` or already in the `obsidian links` output
- Don't link inside time entry lines
- Link known entities freely without asking the user

### Phase 4: Extract Long Sections

Identify sections that are >~20 lines or contain substantial standalone content worth its own note.

For each extractable section:

1. **Determine destination**: `Projects/` subtree or `Topics/` based on content
2. **Create the new note** using `obsidian create path="{destination}" content="{formatted content}"`:
   ```markdown
   # {Title}

   {Extracted content}

   ## Related
   - [[Daily Notes/{date}]]
   ```
3. **Replace the section** in the daily note with a brief summary + `[[wikilink]]` to the new note

**Present all proposed extractions to the user for approval before executing.** Show what would be extracted, where it would go, and what the replacement summary would look like.

### Phase 4b: Suggest New Entities

Identify mentions of people, projects, or topics that don't match any existing vault note.

For each candidate name, run `qmd query "{name}"` to check if the entity already exists under a different spelling or alias before suggesting creation. If qmd returns a high-confidence match (>70%), skip the suggestion and use the existing entity instead.

Present remaining candidates:
```
It looks like **Jane Smith** and **ProjectX** are mentioned but don't have vault pages yet.
Want me to create them?
```

For each confirmed new entity, create the note following vault conventions:

- **Person**: `$VAULT/Persons/{Name}.md`
  ```markdown
  ---
  aliases:
    - {short name}
  ---
  # {Full Name}

  **Role**: {if known}
  **Projects**: {if known}

  ## Notes
  ```

- **Project**: `$VAULT/Projects/{Name}.md` (or appropriate subdirectory)
  ```markdown
  # {Project Name}

  {Brief description if known}

  ## Related
  ```

- **Topic**: `$VAULT/Topics/{Name}.md`
  ```markdown
  # {Topic Name}

  {Brief definition if known}

  ## Related

  ## Notes
  ```

After creating new entities:
- Add them to the respective MOC file (e.g., Persons MOC, Topics MOC) if one exists
- Link them in the daily note (they now exist as vault pages)

### Phase 4c: Suggest Todo Completions

Scan unchecked todos on project pages against today's content to suggest completions with high confidence.

1. **Collect unchecked todos**: Run `obsidian tasks todo` to get all open todos from project files. Filter to projects referenced in today's time entries.
2. **Search for completion evidence**: For each unchecked todo, run `qmd query "{todo text}"` to search for evidence across today's daily note, meeting notes, and coding sessions. Look for high-confidence semantic matches.
3. **Match todos to evidence** — for each unchecked todo, check for HIGH confidence matches only:
   - Strong semantic similarity between todo text and evidence (qmd score >70%)
   - Explicit completion signals ("merged PR #X", "completed", "done", "shipped", "deployed")
4. **Present suggestions with evidence**:
   > These todos appear done based on today's work:
   > - `review PRs` (Technomic.md) — Evidence: wrote detailed reviews for PRs #650, #636, #571, #469
   > - `fix vector search` (Technomic.md) — Evidence: coding session [[2026-02-20--TechnomicIgnite--fix-vector-search]] shows fixes deployed
   > Mark as complete? (✅ 2026-02-20)
5. **If approved**, check off the todos on the project page: change `- [ ]` to `- [x]` and append ` ✅ {date}`. The Tasks plugin completion format ensures they appear in the daily note's "Done today" dataview.

**Rules:**
- Never suggest more than 5 completions at once
- Skip anything below ~80% confidence — better to miss one than suggest a false positive
- Never auto-complete without user approval
- If no high-confidence matches found, skip this phase silently

### Phase 4d: Freeze "Done today" on Previous Days

When refining a **previous day's** note (not today), convert the "Done today" dataview query into plain markdown so it becomes a permanent historical record.

1. **Check if the target date is before today**. If refining today's note, skip this phase entirely.
2. **Find the `### Done today` section** and its dataview code block.
3. **Read completed todos**: Run `obsidian tasks done` and filter the output for items containing `✅ {target-date}`.
4. **Build plain markdown** from the results:
   ```markdown
   ### Done today
   - [x] [[Technomic]] - Investigate feature-22 login issue ✅ 2026-03-03
   - [x] [[AI Upskill]] - Attend Panama Canal meeting ✅ 2026-03-03
   ```
   Prefix each item with `[[Project]]` for context since the items originally live on project pages.
5. **Replace the dataview block** with the plain markdown list.
6. **Clean up project pages**: Remove the now-frozen `- [x] ... ✅ {target-date}` items from the project files' `## Todos` sections to keep them tidy.

If no completed tasks found for the target date, replace the dataview with an empty section (just the heading).

### Phase 4e: Move Inline Todos to Project Pages

Scan the daily note for `- [ ]` lines written outside of dataview blocks and move them to the appropriate project page.

1. **Find inline todos**: Scan the daily note for lines matching `- [ ] [[Project]] ...` that are NOT inside a dataview code block.
2. **For each todo**:
   - Extract the project name from the `[[Project]]` wikilink
   - Find the corresponding project file in `$VAULT/Projects/`
   - Check the `## Todos` section for duplicates (fuzzy match)
3. **Present proposed moves**:
   > Moving inline todos to project pages:
   > - `- [ ] [[Technomic]] fix login bug` → Technomic.md `## Todos`
   > - `- [ ] [[KHov]] test Docker build` → Khov.md `## Todos`
4. **If approved**:
   - Append each todo (without the `[[Project]]` prefix) to the project file's `## Todos` section
   - Remove the original line from the daily note

If no inline todos found, skip this phase silently.

### Phase 5: Apply & Confirm

1. **Show a summary** of all proposed changes before writing:
   - Prose improvements (brief description)
   - Wikilinks added (list them)
   - Sections extracted (destination paths)
   - New entities created (paths)
2. **Get user approval** before applying
3. **Apply changes**: edit the daily note, create any extracted/new entity notes
4. **Report**: what was changed, what was linked, what was extracted, what was created

### Phase 6: Update Project Recent Activity

After all daily note changes are applied, update each referenced project's note with a summary of today's activity.

1. **Identify projects** from today's time entries in the daily note.
2. **For each project** with a note in `$VAULT/Projects/`:
   - Read the existing `## Recent Activity` section (or prepare to create it)
   - Build today's entry: `- **{date}**: {hours}h — {brief summary} (meetings: [[links]], coding: [[links]])`
   - Prune entries older than 7 days from the section
   - Insert the `## Recent Activity` section before `## Key Features` or at the end of the note if no logical insertion point
3. **Check idempotency**: If an entry for today's date already exists, update it rather than duplicating.
4. **Present all proposed project note updates** for approval before applying.
5. **Apply changes** if approved.

## Key Rules

- **Never modify time entries** — the bullet list at the top is structured data
- **Todos live on project pages** — open todos are under `## Todos` in each project file. Daily notes show them via dataview queries (`### Done today` for completed, `### Open todos` for unchecked).
- **Link known entities freely** — no need to ask for entities that already exist
- **Offer to create unknown entities** — ask before creating new vault pages
- **Author's voice** — improve clarity without rewriting style
- **Idempotent** — running twice shouldn't cause issues (don't re-extract already-extracted sections, don't double-link, don't re-freeze already-frozen Done today sections)
- **Show before applying** — always preview changes for user approval (unless `--auto` mode)
