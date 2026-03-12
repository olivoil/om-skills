---
name: obsidian-weekly-rollup
description: Generate a weekly summary from daily notes — time totals, meeting highlights, coding sessions, key decisions, and todo progress. Use when the user types /rollup or asks for a weekly summary.
allowed-tools: Read, Edit, Bash(obsidian *)
---

# Weekly Rollup

Generate a weekly summary note from daily notes, aggregating time entries, meetings, coding sessions, decisions, and todo progress.

## Workflow

### Phase 1: Setup

1. Run `obsidian vault info=path` to get the vault root.
2. Determine the target week:
   - If an argument is provided (e.g., `/obsidian-weekly-rollup 2026-02-17`), use the week containing that date
   - Otherwise, use the current week
3. Calculate Monday–Sunday dates for the target week.
4. Compute the ISO week number (`YYYY-WNN`) for the output filename.

### Phase 2: Collect Data

Read all daily notes for the target week.

For each day that has a note:

1. **Time entries**: Run `obsidian read path="Daily Notes/{date}.md"` and parse the structured bullet list at the top. Extract project, activity description, and hours for each line.
2. **Meetings & Coding sessions**: Run `obsidian links file="{date}"` to get outgoing links. Filter for paths starting with `Meetings/` and `Coding/`. Read each linked note to get its summary (first paragraph after `# Title`), project, and participants.
3. **Todos**: Run `obsidian tasks todo` to get all open todos from project files. Run `obsidian tasks done` and filter for items where the completion date falls within the target week. Track which were completed (with date) vs still open.
4. **Decisions**: For each meeting note, extract items from `## Decisions` sections.

### Phase 3: Aggregate

1. **Time by project**: Sum hours per project across all days. Break down by work type (meetings, dev, etc.) where inferable from the activity description.
2. **Meetings**: Group by project. Include one-line summary for each.
3. **Coding sessions**: List with one-line summaries.
4. **Todo stats**: Count completed, still open, and newly added during the week.
5. **Key decisions**: Collect from all meeting notes, attributed to the meeting.

### Phase 4: Generate Weekly Note

Build the weekly note content, then create it with `obsidian create path="Weekly Notes/{YYYY}-W{NN}.md" content="{content}"`. If the file already exists and overwrite is approved, add the `overwrite` flag:

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
2. **Check idempotency**: If a note for this week already exists (check with `obsidian files folder="Weekly Notes"`), show a diff of what would change and ask whether to overwrite or skip.
3. **Write the note** if approved using `obsidian create` (with `overwrite` if replacing).

## Key Rules

- **Read-only on daily notes** — never modify daily notes or time entries
- **Read-only on meeting/coding notes** — only read them for aggregation
- **Show before writing** — always preview the weekly note for approval
- **Idempotent** — re-running for the same week should produce the same output (or update an existing note)
- **Graceful with missing data** — if a day has no note, skip it. If a section is empty, omit it from the output.
