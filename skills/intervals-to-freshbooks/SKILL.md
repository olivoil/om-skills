---
name: intervals-to-freshbooks
description: Copy a week's worth of time entries from Intervals to FreshBooks. Use when asked to sync time entries between Intervals and FreshBooks.
allowed-tools: mcp__chrome-devtools__*, Read, Write, Edit, Bash
---

# Intervals → FreshBooks Time Entry Sync

Copy weekly time entries from Intervals to FreshBooks.

**Reading from Intervals**: Browser automation via MCP chrome-devtools
**Writing to FreshBooks**: API via `scripts/freshbooks-api.sh`

## Prerequisites

1. Chrome/Chromium running with `--remote-debugging-port=9222`
2. Intervals weekly timesheet open: `https://bhi.intervalsonline.com/time/`
3. chrome-devtools MCP server configured
4. FreshBooks API credentials configured in `~/.config/freshbooks/credentials.json`

## Workflow

### Phase 1: Verify Prerequisites

1. Call `list_pages` to find Intervals browser tab
2. Find Intervals tab (URL contains `intervalsonline.com/time/`)
3. If missing, inform user and stop

### Phase 2: Read from Intervals

1. Select the Intervals tab using `select_page`
2. Run `scripts/read-intervals.js` using `evaluate_script`
3. Display the entries to user for review

**The script reads from the summary table** which has this structure:
- `td.col-timesheet-clientproject` contains "Client\nProject"
- Following cells contain: Billable, Mon, Tue, Wed, Thu, Fri, Sat, Sun, Total

**Output format:**
```javascript
{
  success: true,
  week: "January 05, 2026",
  entries: [
    { client: "Technomic", project: "Ignite App...", billable: true,
      hours: { mon: 7.5, tue: 4.5, wed: 4.5, thu: 0, fri: 4.5, sat: 0, sun: 0 },
      totalHours: 21 }
  ],
  grandTotal: 47.75
}
```

### Phase 3: Map Entries

For each Intervals entry, determine the FreshBooks destination:
- **Client** is always required for invoicing (defaults to "EXSquared")
- **Project** is optional - use when work is for a specific project
- If unmapped, ask user for the FreshBooks mapping
- Update `references/project-mappings.md` with new mappings

**Mapping examples:**
| Intervals Client | Intervals Project | FB Client | FB Project |
|-----------------|-------------------|-----------|------------|
| Technomic | Ignite App... | EXSquared | Technomic |
| EWG - Neuron | Feature Enhancement | EXSquared | EWG |
| EX Squared Services | Meeting | EXSquared | (none) |
| EX Squared Services | Biz Dev / Sales | EXSquared | (none) |

### Phase 4: Create FreshBooks Time Entries via API

Use `scripts/freshbooks-api.sh` to create time entries:

```bash
# List available projects and clients
./scripts/freshbooks-api.sh projects
./scripts/freshbooks-api.sh clients

# Create a time entry
./scripts/freshbooks-api.sh create-time-entry \
  --project "<name>" | --client "<name>" \
  --date <YYYY-MM-DD> \
  --hours <hours> \
  [--note "<note>"]
```

For each Intervals entry with hours on a given day:
1. Check mapping type (project or client)
2. Call `create-time-entry` for each day with hours > 0
3. Include a note (e.g., the Intervals project name or work type)

**Examples:**
```bash
# With project (client defaults to EXSquared)
./scripts/freshbooks-api.sh create-time-entry \
  --project "Technomic" \
  --date "2026-01-06" \
  --hours 7.5 \
  --note "Development"

# Client only - no project (e.g., internal meetings)
./scripts/freshbooks-api.sh create-time-entry \
  --date "2026-01-06" \
  --hours 1.0 \
  --note "Meeting"

# Different client (rare)
./scripts/freshbooks-api.sh create-time-entry \
  --client "Rocksauce Studios" \
  --date "2026-01-06" \
  --hours 1.0
```

### Phase 5: Verify

1. List created entries:
   ```bash
   ./scripts/freshbooks-api.sh list-time-entries --from "2026-01-05" --to "2026-01-11"
   ```
2. Display summary of entries created
3. Open or refresh FreshBooks in the browser for visual review:
   - Use `list_pages` to find FreshBooks tab
   - If found: `select_page` then `navigate_page` with `type: "reload"`
   - If not found: `new_page` with FreshBooks week URL

   ```
   URL format: https://my.freshbooks.com/#/time-tracking/week?week=YYYY-MM-DD
   (where YYYY-MM-DD is the Monday of the week)
   ```

## Scripts

### `read-intervals.js`

Reads the Intervals weekly summary table. No configuration needed.
Run via `evaluate_script` - returns structured entry data.

### `freshbooks-api.sh`

Shell script for FreshBooks API operations. Supports 1Password `op://` references in credentials.

**Commands:**
- `projects` - List all FreshBooks projects
- `clients` - List all FreshBooks clients
- `project-id <name>` - Get project ID by name
- `client-id <name>` - Get client ID by name
- `create-time-entry` - Create a time entry
  - `--client, -c <name>` - FreshBooks client (default: EXSquared)
  - `--project, -p <name>` - FreshBooks project (optional)
  - `--date, -d <YYYY-MM-DD>` - Date of the entry (required)
  - `--hours, -h <hours>` - Hours worked (required)
  - `--note, -n <note>` - Description (optional)
- `list-time-entries` - List time entries
  - `--from, -f <YYYY-MM-DD>` - Start date
  - `--to, -t <YYYY-MM-DD>` - End date

**Credentials:** `~/.config/freshbooks/credentials.json`
```json
{
  "client_id": "op://Private/Freshbooks API/username",
  "client_secret": "op://Private/Freshbooks API/credential",
  "redirect_uri": "https://localhost/callback"
}
```

**First-time setup:**
```bash
./scripts/freshbooks-oauth.sh authorize   # Get auth URL
./scripts/freshbooks-oauth.sh exchange <code>  # Exchange code for tokens
./scripts/freshbooks-oauth.sh me          # Test connection
```

## Key Technical Details

### Intervals Summary Table
- Rows: `tr` containing `td.col-timesheet-clientproject`
- Client/Project cell: text split by `\n` (Client first, Project second)
- Hour cells follow: index 2-8 for Mon-Sun, index 9 for Total

### FreshBooks API

**Time Entry endpoint:** `POST /timetracking/business/{business_id}/time_entries`

**Payload:**
```json
{
  "time_entry": {
    "is_logged": true,
    "duration": 27000,
    "note": "Development",
    "started_at": "2026-01-06T09:00:00.000Z",
    "project_id": 12447219,
    "identity_id": 123456
  }
}
```

- `duration` is in seconds (7.5 hours = 27000 seconds)
- `started_at` is the date of the entry
- `project_id` is looked up by project name
- `identity_id` is the user's FreshBooks identity

### Hour Format
- Intervals: decimal hours (e.g., "7.5")
- API: seconds (multiply by 3600)

## Common Issues

1. **Project not found**: Run `./scripts/freshbooks-api.sh projects` to see available project names.

2. **Token expired**: The script auto-refreshes tokens, but if it fails, run `./scripts/freshbooks-oauth.sh refresh`.

3. **Week mismatch**: Make sure you're reading the correct week from Intervals.

4. **1Password CLI**: If using `op://` references, ensure you're signed in (`op signin`).
