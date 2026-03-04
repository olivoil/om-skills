---
name: rollup
description: Generate a weekly summary from daily notes — time totals, meeting highlights, coding sessions, key decisions, and todo progress. Use when the user types /rollup or asks for a weekly summary.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(echo $*)
---

# Weekly Rollup

Generate a weekly summary note from daily notes, aggregating time entries, meetings, coding sessions, decisions, and todo progress.

## Workflow

### Phase 1: Setup

1. Run `echo $OBSIDIAN_VAULT_PATH` to get the vault root. If empty, ask the user for the path.
2. Determine the target week:
   - If an argument is provided (e.g., `/rollup 2026-02-17`), use the week containing that date
   - Otherwise, use the current week
3. Calculate Monday–Sunday dates for the target week.
4. Compute the ISO week number (`YYYY-WNN`) for the output filename.

### Phase 2: Collect Data

Read all daily notes for the target week from `$VAULT/Daily Notes/`.

For each day that has a note:

1. **Time entries**: Parse the structured bullet list at the top. Extract project, activity description, and hours for each line.
2. **Meetings**: Find wikilinks to `Meetings/` notes. Read each meeting note to get its summary (first paragraph after `# Title`), project, and participants.
3. **Coding sessions**: Find wikilinks to `Coding/` notes. Read each to get its summary.
4. **Todos**: Collect completed todos from project pages (items matching `- [x] ... ✅ {date}` where the date falls within the target week). Also collect all open todos (`- [ ]`) from the `## Todos` section of each project file in `$VAULT/Projects/`. Track which were completed (with date) vs still open.
5. **Decisions**: For each meeting note, extract items from `## Decisions` sections.

### Phase 3: Aggregate

1. **Time by project**: Sum hours per project across all days. Break down by work type (meetings, dev, etc.) where inferable from the activity description.
2. **Meetings**: Group by project. Include one-line summary for each.
3. **Coding sessions**: List with one-line summaries.
4. **Todo stats**: Count completed, still open, and newly added during the week.
5. **Key decisions**: Collect from all meeting notes, attributed to the meeting.

### Phase 4: Generate Weekly Note

Build the weekly note at `$VAULT/Weekly Notes/{YYYY}-W{NN}.md`:

```markdown
# Week of {Monday date}

## Time Summary
| Project | Hours | Activities |
|---------|-------|-----------|
| {Project} | {total} | {comma-separated activities} |
| ... | ... | ... |

**Total: {sum} hours**

## Meetings
### [[{Project}]]
- [[{Meeting Note Title}]] — {one-line summary}

## Coding Sessions
- [[{Coding Note Title}]] — {one-line summary}

## Key Decisions
- {decision} (from [[{Meeting Note}]])

## Todos
- Completed: {count} | Open: {count} | New this week: {count}

### Completed This Week
- [x] {todo text} ✅ {date} ([[Project]])

### Open
- [ ] {todo text} ([[Project]])
```

### Phase 5: Review & Write

1. **Present the generated note** to the user for review.
2. **Create the directory** `$VAULT/Weekly Notes/` if it doesn't exist.
3. **Check idempotency**: If a note for this week already exists, show a diff of what would change and ask whether to overwrite or skip.
4. **Write the note** if approved.

## Key Rules

- **Read-only on daily notes** — never modify daily notes or time entries
- **Read-only on meeting/coding notes** — only read them for aggregation
- **Show before writing** — always preview the weekly note for approval
- **Idempotent** — re-running for the same week should produce the same output (or update an existing note)
- **Graceful with missing data** — if a day has no note, skip it. If a section is empty, omit it from the output.
