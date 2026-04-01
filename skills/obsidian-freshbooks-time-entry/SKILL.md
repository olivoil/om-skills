---
name: obsidian-freshbooks-time-entry
description: Sync Intervals time entries from SQLite to FreshBooks. Faster than browser-based sync since it reads local data. Use when asked to sync time to FreshBooks, enter FreshBooks time, or fill FreshBooks from Intervals.
allowed-tools: Bash(bash *obsidian-freshbooks-time-entry/scripts/*), Bash(bash *intervals-to-freshbooks/scripts/freshbooks-api.sh *), mcp__chrome-devtools__list_pages, mcp__chrome-devtools__select_page, mcp__chrome-devtools__navigate_page, Read, Write, Edit
---

# Intervals → FreshBooks Time Entry Sync (SQLite)

Sync time entries from the local SQLite database to FreshBooks. Reads Intervals data from SQLite instead of browser automation.

**Reading from**: SQLite `intervals_time_entries` table via `scripts/query-intervals.sh`
**Writing to**: FreshBooks API via `intervals-to-freshbooks/scripts/freshbooks-api.sh`
**Persisting**: SQLite `freshbooks_time_entries` table via `scripts/insert-freshbooks.sh`
**Mapping**: `intervals-to-freshbooks/references/project-mappings.md`

## Prerequisites

1. SQLite database at `$VAULT/.claude/time-entries.db` with `intervals_time_entries` populated
2. FreshBooks API credentials in `~/.config/freshbooks/credentials.json`
3. Chrome with `--remote-debugging-port=9222` (for refreshing FreshBooks at the end)

`$VAULT` = `/home/olivier/Code/github.com/olivoil/obsidian`
`$DB` = `$VAULT/.claude/time-entries.db`
`$SKILL` = this skill's base directory
`$FB_SKILL` = `$SKILL/../intervals-to-freshbooks`

## Scripts

### `scripts/query-intervals.sh`

Query Intervals time entries grouped by date + project.

```bash
bash $SKILL/scripts/query-intervals.sh $DB [--from YYYY-MM-DD] [--to YYYY-MM-DD]
```

Output: TSV with columns `date`, `project`, `hours`

### `scripts/query-freshbooks.sh`

Query FreshBooks time entries from SQLite.

```bash
bash $SKILL/scripts/query-freshbooks.sh $DB [--from YYYY-MM-DD] [--to YYYY-MM-DD]
```

Output: TSV with columns `date`, `project`, `description`, `hours`

### `scripts/insert-freshbooks.sh`

Insert a FreshBooks entry into the local SQLite database.

```bash
bash $SKILL/scripts/insert-freshbooks.sh $DB \
  --date YYYY-MM-DD \
  --project "<name>" \
  --hours <hours> \
  --description "<desc>" \
  [--entry-id <fb_id>]
```

### `freshbooks-api.sh` (from intervals-to-freshbooks)

Create entries in FreshBooks via API.

```bash
bash $FB_SKILL/scripts/freshbooks-api.sh create-time-entry \
  [--project "<name>" | --client "<name>"] \
  --date YYYY-MM-DD \
  --hours <hours> \
  [--note "<note>"]
```

Other commands: `projects`, `clients`, `list-time-entries --from DATE --to DATE`

## Workflow

### Phase 1: Read Project Mappings

Read the mapping file at `$FB_SKILL/references/project-mappings.md`.

Build a lookup from Intervals project name to FreshBooks destination. Match using CONTAINS (Intervals project names may have SOW numbers appended like `(20250040)`).

| Intervals Project (contains) | FB Project | FB Note | Has FB Project? |
|-------------------------------|-----------|---------|-----------------|
| Ignite Application Development | Technomic | Development | yes |
| Optimizely CMS | K Hovnanian | Development | yes |
| Drees Maintenance | Drees | Development | yes |
| DHDC Pre Buyer | Drees | Development | yes |
| EWG Feature Enhancement | EWG | Development | yes |
| EWG App v3 | EWG | Development | yes |
| Mattamy Homes | Mattamy Homes | Development | yes |
| CDS Digital Product | SLB | Development | yes |
| Monthly Maintenance Agreement | TeleDynamics | Development | yes |
| YPO - ProductOps | YPO | Development | yes |
| Meeting | (none) | Meetings | no (client-only) |
| Biz Dev / Sales | (none) | Business Development | no (client-only) |
| Training | (none) | Training | no (client-only) |
| Recruiting | (none) | Recruiting | no (client-only) |

**Client-only entries** (no FB project) use `--client EXSquared` without `--project`. In SQLite they are stored with project = "EXSquared".

### Phase 2: Query SQLite for Gaps

1. Run `query-intervals.sh` to get Intervals daily totals by project
2. Run `query-freshbooks.sh` to get existing FreshBooks entries
3. For each Intervals row, map the project name to FB project + note using the lookup
4. Check if FreshBooks already has a matching row for that date + FB project + note
5. Collect all unmatched rows as gaps

**If an Intervals project name doesn't match any mapping**, flag it and ask the user. Update `$FB_SKILL/references/project-mappings.md` with the new mapping.

**Multiple Intervals projects may map to the same FB project.** Sum their hours per date before comparing. For example, if Intervals has "Optimizely CMS Decoupling" (3h) and "Optimizely CMS Health Check" (1h) on the same day, that's 4h total for "K Hovnanian" in FreshBooks.

### Phase 3: Display Gaps and Confirm

Present gaps grouped by week:

```
**Week of March 2-8, 2026 (41.25h)**
| Date | FB Project | Hours | Note |
|------|-----------|------:|------|
| 2026-03-02 | K Hovnanian | 5.0 | Development |
| 2026-03-02 | Technomic | 0.5 | Development |
| 2026-03-02 | EXSquared | 1.0 | Meetings |
| ... | ... | ... | ... |
```

Ask the user to confirm before proceeding. If no gaps found, report that everything is synced.

### Phase 4: Create FreshBooks Time Entries

For entries **with a FB project**:
```bash
bash $FB_SKILL/scripts/freshbooks-api.sh create-time-entry \
  --project "<FB Project>" --date "<YYYY-MM-DD>" --hours <hours> --note "<Note>"
```

For **client-only entries** (Meetings, Biz Dev, etc.):
```bash
bash $FB_SKILL/scripts/freshbooks-api.sh create-time-entry \
  --date "<YYYY-MM-DD>" --hours <hours> --note "<Note>"
```

Run entries in parallel batches (by project) for speed.

### Phase 5: Persist to SQLite

For each created entry, run `insert-freshbooks.sh`:

```bash
bash $SKILL/scripts/insert-freshbooks.sh $DB \
  --date "YYYY-MM-DD" \
  --project "<FB Project or EXSquared>" \
  --hours <hours> \
  --description "<Note>" \
  --entry-id "<fb_entry_id>"
```

- Entries with a FB project: use the project name (e.g. "Technomic")
- Client-only entries: use "EXSquared" as project

### Phase 6: Update Daily Notes

For each date with new entries, append a `### FreshBooks` section to `$VAULT/Daily Notes/YYYY-MM-DD.md`:

```markdown
------
### FreshBooks
| Project | Hours | Description |
|---------|------:|-------------|
| K Hovnanian | 5.0 | Development |
| Technomic | 0.5 | Development |
| **Total** | **8.0** | |
```

- If `### FreshBooks` already exists in the note, replace it
- If the daily note doesn't exist, create it with a minimal header
- Right-align the Hours column
- Add a bold **Total** row

### Phase 7: Refresh FreshBooks Browser

1. Call `list_pages` to find a FreshBooks tab
2. If found: `select_page` then `navigate_page` to the relevant week
3. If not found: open a `new_page` with the FreshBooks week URL

```
URL format: https://my.freshbooks.com/#/time-tracking/week?week=YYYY-MM-DD
(where YYYY-MM-DD is the Monday of the first week with new entries)
```
