# Design: obsidian-freshbooks-time-entry

## Purpose

Sync time entries from the local SQLite database (Intervals data) to FreshBooks, skipping anything already synced. Faster than the browser-based `intervals-to-freshbooks` since it reads from SQLite instead of scraping the Intervals web UI.

## Workflow

1. **Query SQLite for gaps** -- For each date+project combo in `intervals_time_entries`, sum the hours, map the Intervals project name to the FreshBooks project name (using `intervals-to-freshbooks/references/project-mappings.md`), then compare against `freshbooks_time_entries`. Any date+project with Intervals hours but no matching FreshBooks entry is a gap.

2. **Display gaps for confirmation** -- Show the user a table of what will be created: date, FreshBooks project, hours, note (e.g. "Development" or "Meetings" based on the mapping). Ask for confirmation before proceeding.

3. **Create FreshBooks entries via API** -- Use the existing `freshbooks-api.sh` script from `intervals-to-freshbooks`.

4. **Persist to SQLite + daily notes** -- Insert into `freshbooks_time_entries`, append `### FreshBooks` section to daily notes (same format as current skill).

5. **Refresh FreshBooks browser** -- Navigate the FreshBooks tab to the relevant week for visual verification.

## Project Name Mapping

The skill reads the mapping table from `intervals-to-freshbooks/references/project-mappings.md`. The Intervals SQLite `project` column contains the Intervals project name (e.g. "Ignite Application Development & Support"), which maps to a FreshBooks project (e.g. "Technomic") or client-only entry (e.g. "EXSquared" for Meetings).

Key mapping logic:
- Match Intervals project name against the "Intervals Project" column (fuzzy, since SQLite may have SOW numbers appended like `(20250040)`)
- Use the "FreshBooks Service" column as the note (Development, Meetings, Business Development, etc.)
- If no mapping found, flag it and ask the user

## Gap Detection

Compare by date + mapped FreshBooks project. For each date, sum Intervals hours per mapped FB project. If a date+project exists in Intervals but not in FreshBooks, it's a gap.

## What It Does NOT Do

- No browser automation for reading Intervals (that's the whole point)
- No modification of Intervals data
- Does not replace the existing `intervals-to-freshbooks` skill (still useful if SQLite data is stale)

## Dependencies

- SQLite database at `$OBSIDIAN_VAULT/.claude/time-entries.db` with `intervals_time_entries` and `freshbooks_time_entries` tables
- `intervals-to-freshbooks/scripts/freshbooks-api.sh` for API calls
- `intervals-to-freshbooks/references/project-mappings.md` for project name mapping
- chrome-devtools MCP (only for refreshing FreshBooks browser tab at the end)
