# Obsidian CLI & QMD Integration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace manual vault operations in the four obsidian skills with `obsidian` CLI and `qmd` commands where they provide clearer, more reliable, or more capable alternatives.

**Architecture:** Surgical replacements — swap individual operations for the better tool. Keep Read/Write/Edit for complex multi-line edits. `obsidian` CLI for vault-native ops, `qmd` for semantic search, Edit for targeted modifications.

**Tech Stack:** Obsidian CLI (`obsidian`), QMD (`qmd`), existing bash scripts

**Design doc:** `docs/plans/2026-03-12-obsidian-cli-qmd-integration-design.md`

---

### Task 1: Update `obsidian-refine-daily-note` — allowed-tools and Phase 0

**Files:**
- Modify: `skills/refine/SKILL.md:4` (allowed-tools)
- Modify: `skills/refine/SKILL.md:13-17` (Phase 0)

**Step 1: Update allowed-tools**

In the frontmatter, replace:
```
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(echo $*), ToolSearch
```
With:
```
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(obsidian *), Bash(qmd *), ToolSearch
```

**Step 2: Update Phase 0: Setup**

Replace the three setup steps with:
```markdown
### Phase 0: Setup

1. Run `obsidian vault info=path` to get the vault root.
2. Determine the target date: use the argument if provided (e.g., `/obsidian-refine-daily-note 2026-02-14`), otherwise use today.
3. Run `obsidian daily:read` to get today's daily note content. If a different date, use `obsidian read path="Daily Notes/{date}.md"`. Error if missing.
```

**Step 3: Commit**

```bash
git add skills/refine/SKILL.md
git commit -m "refine: use obsidian CLI for setup phase and allowed-tools"
```

---

### Task 2: Update `obsidian-refine-daily-note` — Phase 1 (Discover Vault Entities)

**Files:**
- Modify: `skills/refine/SKILL.md:19-29` (Phase 1)

**Step 1: Replace Phase 1 content**

Replace Phase 1 with:
```markdown
### Phase 1: Discover Vault Entities

Build a catalog of all known entities so you can match them against the daily note text.

1. **Projects**: Run `obsidian files folder=Projects` — extract project names from filenames
2. **People**: Run `obsidian files folder=Persons` to list person files. For each, run `obsidian property:read name=aliases path="Persons/{name}.md"` to get aliases.
3. **Topics**: Run `obsidian files folder=Topics` — extract topic names from filenames
4. **Coding sessions**: Run `obsidian files folder=Coding` — for cross-reference awareness
5. **Meetings**: Run `obsidian files folder=Meetings` — for cross-reference awareness
6. **Tags**: Run `obsidian tags counts` to build a tag catalog

This gives you the full entity catalog to match against the daily note.
```

**Step 2: Commit**

```bash
git add skills/refine/SKILL.md
git commit -m "refine: use obsidian CLI for entity discovery"
```

---

### Task 3: Update `obsidian-refine-daily-note` — Phase 3 (Add Missing Wikilinks)

**Files:**
- Modify: `skills/refine/SKILL.md` (Phase 3: Add Missing Wikilinks)

**Step 1: Add obsidian CLI commands to Phase 3**

Replace Phase 3 with:
```markdown
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
```

**Step 2: Commit**

```bash
git add skills/refine/SKILL.md
git commit -m "refine: use obsidian unresolved and links for wikilink phase"
```

---

### Task 4: Update `obsidian-refine-daily-note` — Phase 4, 4b, 4c, 4d (Extract, Entities, Todos)

**Files:**
- Modify: `skills/refine/SKILL.md` (Phases 4, 4b, 4c, 4d)

**Step 1: Update Phase 4 — note creation**

In Phase 4 (Extract Long Sections), step 2, replace:
```
2. **Create the new note** with proper format:
```
With instructions to use `obsidian create`:
```
2. **Create the new note** using `obsidian create path="{destination}" content="{formatted content}"`:
```

**Step 2: Update Phase 4b — add qmd for fuzzy entity matching**

After the line "Identify mentions of people, projects, or topics that don't match any existing vault note.", add:

```markdown
For each candidate name, run `qmd query "{name}"` to check if the entity already exists under a different spelling or alias before suggesting creation. If qmd returns a high-confidence match (>70%), skip the suggestion and use the existing entity instead.
```

**Step 3: Update Phase 4c — use obsidian tasks + qmd**

Replace Phase 4c steps 1-3 with:
```markdown
1. **Collect unchecked todos**: Run `obsidian tasks todo` to get all open todos from project files. Filter to projects referenced in today's time entries.
2. **Search for completion evidence**: For each unchecked todo, run `qmd query "{todo text}"` to search for evidence across today's daily note, meeting notes, and coding sessions. Look for high-confidence semantic matches.
3. **Match todos to evidence** — for each unchecked todo, check for HIGH confidence matches only:
   - Strong semantic similarity between todo text and evidence (qmd score >70%)
   - Explicit completion signals ("merged PR #X", "completed", "done", "shipped", "deployed")
```

**Step 4: Update Phase 4d — use obsidian tasks done**

Replace Phase 4d step 3 with:
```markdown
3. **Read completed todos**: Run `obsidian tasks done` and filter the output for items containing `✅ {target-date}`.
```

**Step 5: Commit**

```bash
git add skills/refine/SKILL.md
git commit -m "refine: use obsidian create, tasks, and qmd for phases 4-4d"
```

---

### Task 5: Update `obsidian-session-summary`

**Files:**
- Modify: `skills/done/SKILL.md`

**Step 1: Update allowed-tools**

Replace:
```
allowed-tools: Read, Write, Edit, Bash(git *)
```
With:
```
allowed-tools: Read, Edit, Bash(git *), Bash(obsidian *)
```

**Step 2: Update Step 0 (vault path)**

Replace:
```
Run `echo $OBSIDIAN_VAULT_PATH` to get the Obsidian vault root directory. If empty, ask the user for the path before proceeding.
```
With:
```
Run `obsidian vault info=path` to get the Obsidian vault root directory.
```

**Step 3: Update Step 3 (write session file)**

Replace the file existence check and write instructions. After "If a file already exists at that path...", add:
```
Use `obsidian files folder=Coding` to check for existing files with the same date-repo-branch prefix when determining the counter.
```

Replace the write instruction with:
```
Use `obsidian create path="Coding/{filename}.md" content="{formatted content}"` to create the session file.
```

**Step 4: Update Step 4 (link from daily note)**

Replace:
```
**Path**: `$OBSIDIAN_VAULT_PATH/Daily Notes/{date}.md`

If the daily note doesn't exist, create it.

Look for an existing `### Coding Sessions` section.
```
With:
```
Run `obsidian daily:read` to get the daily note content.

If the daily note doesn't exist, create it with `obsidian create path="Daily Notes/{date}.md" content="---\ndate: {date}\n---"`.

Look for an existing `### Coding Sessions` section.
```

**Step 5: Commit**

```bash
git add skills/done/SKILL.md
git commit -m "session-summary: use obsidian CLI for vault path, file creation, and daily note"
```

---

### Task 6: Update `obsidian-weekly-rollup`

**Files:**
- Modify: `skills/rollup/SKILL.md`

**Step 1: Update allowed-tools**

Replace:
```
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(echo $*)
```
With:
```
allowed-tools: Read, Edit, Bash(obsidian *)
```

**Step 2: Update Phase 1 (Setup)**

Replace:
```
1. Run `echo $OBSIDIAN_VAULT_PATH` to get the vault root. If empty, ask the user for the path.
```
With:
```
1. Run `obsidian vault info=path` to get the vault root.
```

**Step 3: Update Phase 2 (Collect Data)**

Replace Phase 2 with:
```markdown
### Phase 2: Collect Data

Read all daily notes for the target week.

For each day that has a note:

1. **Time entries**: Run `obsidian read path="Daily Notes/{date}.md"` and parse the structured bullet list at the top. Extract project, activity description, and hours for each line.
2. **Meetings & Coding sessions**: Run `obsidian links file="{date}"` to get outgoing links. Filter for paths starting with `Meetings/` and `Coding/`. Read each linked note to get its summary (first paragraph after `# Title`), project, and participants.
3. **Todos**: Run `obsidian tasks todo` to get all open todos from project files. Run `obsidian tasks done` and filter for items where the completion date falls within the target week. Track which were completed (with date) vs still open.
4. **Decisions**: For each meeting note, extract items from `## Decisions` sections.
```

**Step 4: Update Phase 4 (Generate Weekly Note)**

Replace the write instruction. Change:
```
Build the weekly note at `$VAULT/Weekly Notes/{YYYY}-W{NN}.md`:
```
To:
```
Build the weekly note content, then create it with `obsidian create path="Weekly Notes/{YYYY}-W{NN}.md" content="{content}"`. If the file already exists and overwrite is approved, add the `overwrite` flag.
```

**Step 5: Commit**

```bash
git add skills/rollup/SKILL.md
git commit -m "weekly-rollup: use obsidian CLI for data collection and note creation"
```

---

### Task 7: Update `obsidian-transcribe-meeting` — CLI integration

**Files:**
- Modify: `skills/transcribe-meeting/SKILL.md`

**Step 1: Update allowed-tools**

Add `Bash(obsidian *)` to the allowed-tools list.

**Step 2: Update Phase 0 (Setup)**

Replace:
```
1. Run `echo $OBSIDIAN_VAULT_PATH` to get the vault root. If empty, ask the user for the path.
```
With:
```
1. Run `obsidian vault info=path` to get the vault root.
```

**Step 3: Update Idempotency section**

Replace the grep commands in the Idempotency section:
```markdown
**Rodecaster source** — search by `recording` field:
```
obsidian search query='recording: "{folder}"' path=Meetings
```

**Screen recording source** — search by `video_file` field:
```
obsidian search query='video_file: "{filename}"' path=Meetings
```

**Google Drive / local source** — search by `audio_url` field:
```
obsidian search query='audio_url: "{url-or-path}"' path=Meetings
```

If any search returns results, skip creation and return the existing note path.
```

**Step 4: Update Phase 3 (Create meeting note)**

Replace `Write` instruction with:
```
Use `obsidian create path="Meetings/{date} {Title}.md" content="{formatted content}"` to create the meeting note.
```

**Step 5: Update Phase 5 (Link from daily note)**

Replace reading the daily note with:
```
Run `obsidian daily:read` to check if the daily note references this recording.
```

**Step 6: Update Phase 6 (Link from project note)**

Add after the existing instructions:
```
If the `## Meetings` section already exists, use `obsidian append path="Projects/{project}.md" content="- [[{date} {Title}]]"` to add the link. If the section needs to be created, use `Read` + `Edit`.
```

**Step 7: Commit**

```bash
git add skills/transcribe-meeting/SKILL.md
git commit -m "transcribe-meeting: use obsidian CLI for vault path, search, and note creation"
```

---

### Task 8: Update `obsidian-transcribe-meeting` — Expand Phase 3.5 screenshots to all modes

**Files:**
- Modify: `skills/transcribe-meeting/SKILL.md` (Phase 3.5)

**Step 1: Rewrite Phase 3.5**

Replace the entire Phase 3.5 section with:
```markdown
### Phase 3.5: Extract Key Screenshots

Applies to **all recording modes** (omarchy+rodecaster, omarchy-only, and rodecaster-only).

**Step 1 — Find user screenshots taken during the meeting**:
```bash
bash skills/transcribe-meeting/scripts/find-screenshots.sh "{date}" "{start_time}" "{duration_secs}"
```
This returns a JSON array of screenshots from `~/Pictures/` (or `$OBSIDIAN_SCREENSHOT_DIR` / `$XDG_PICTURES_DIR`) taken during the meeting timeframe (±5 min buffer). Each entry has `path`, `timestamp`, and `offset_secs`. This script has no video dependency — it matches screenshot timestamps against the meeting time window.

**Step 2 — Copy and embed user screenshots**:
For each found screenshot:
- Copy to `$VAULT/Attachments/{meeting-name}-user-{HH-MM-SS}.png`
- Place in the meeting note at the transcript position closest to its `offset_secs`
- Embed using `![[filename.png]]`

**Step 3 — Supplement with ffmpeg-extracted frames** (only when video exists):
This step only applies to `omarchy+rodecaster` and `omarchy-only` modes. Skip entirely for `rodecaster-only`.
- If fewer than 3 user screenshots were found, scan the transcript for visual moments (screen sharing, demos, "as you can see", "look at this", code references, topic transitions) and extract additional frames to reach 3-8 total:
  ```bash
  ffmpeg -ss {secs} -i "{video}" -frames:v 1 -q:v 2 -y "$VAULT/Attachments/{name}-{MM-SS}.png"
  ```
- If 3+ user screenshots were found, skip ffmpeg extraction entirely.

Embed all screenshots at corresponding transcript positions using `![[filename.png]]`.
```

**Step 2: Commit**

```bash
git add skills/transcribe-meeting/SKILL.md
git commit -m "transcribe-meeting: expand screenshot extraction to all recording modes"
```

---

### Task 9: Update CLAUDE.md to reflect skill renames

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update all skill name references**

Replace old skill names with new ones throughout:
- `refine` → `obsidian-refine-daily-note`
- `done` → `obsidian-session-summary`
- `rollup` → `obsidian-weekly-rollup`
- `transcribe-meeting` → `obsidian-transcribe-meeting`
- `code-review` → `github-pr-review`

Update the slash command reference list at the top to use new names:
```markdown
- `/obsidian-refine-daily-note [date]` — Improve daily notes: polish writing, add wikilinks, extract long sections, suggest new entities
- `/obsidian-session-summary` — Capture session summary into Obsidian vault and link from daily note
- `/obsidian-weekly-rollup [date]` — Generate weekly summary from daily notes
- `/obsidian-transcribe-meeting <url-or-path>` — Transcribe meeting recording and create structured meeting note
- `/intervals-time-entry [date]` — Fill Intervals time entries from daily notes
- `/intervals-to-freshbooks [week-start]` — Sync a week of Intervals entries to FreshBooks
- `/github-pr-review` — Review a PR and post findings as inline comments to GitHub
```

**Step 2: Add Obsidian CLI and QMD to Dependencies section**

Add to the Dependencies section:
```markdown
- Obsidian desktop app with CLI enabled (Settings → General → CLI) for vault-native operations
- `qmd` CLI (installed via `bun install -g @tobilu/qmd`) for semantic vault search
```

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md with renamed skills and new CLI dependencies"
```
