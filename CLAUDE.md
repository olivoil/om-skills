# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Claude Code plugin (`tt`) that automates time entry management between **Intervals Online** and **FreshBooks**, with **GitHub** and **Outlook calendar** correlation. It consists of two skills invoked via slash commands:

- `/intervals-time-entry [date]` — Fill Intervals time entries from daily notes (`📅 Daily Notes/YYYY-MM-DD.md`)
- `/intervals-to-freshbooks [week-start]` — Sync a week of Intervals entries to FreshBooks

There is no build system, test suite, or linter. The project is pure JavaScript (browser scripts executed via chrome-devtools MCP) and Bash (API utilities).

## Architecture

### Two-Skill Structure

```
skills/
├── intervals-time-entry/       # Notes → Intervals (browser automation)
│   ├── SKILL.md                # Workflow definition (6 phases + GitHub/Outlook correlation)
│   ├── references/             # Mapping files (project, worktype, github, outlook, people)
│   └── scripts/                # Browser JS + GitHub/Outlook fetch bash scripts
└── intervals-to-freshbooks/    # Intervals → FreshBooks (API + browser)
    ├── SKILL.md                # Workflow definition (5 phases)
    ├── references/             # Intervals→FreshBooks project mappings
    └── scripts/                # Browser JS + FreshBooks API bash scripts
```

Each skill has a `SKILL.md` that defines the complete workflow — these are the authoritative references for how each skill operates.

### Cache System

Cache lives in the **user's project** (not this plugin repo), making the plugin read-only and distributable:

```
<user-project>/.claude/intervals-cache/
├── project-mappings.md        # Discovered project→worktype mappings
├── github-mappings.md         # Learned repo→project associations
├── outlook-mappings.md        # Learned calendar→project associations
├── fetch-github-activity.sh   # Auto-synced script (version-checked)
└── fetch-outlook-calendar.sh  # Auto-synced script (version-checked)
```

This cache-aside pattern means browser inspection only happens once per project — subsequent runs skip directly to filling entries (3-4 MCP calls total vs 50+ without caching).

### Browser Script Conventions

All scripts in `scripts/` are executed via `mcp__chrome-devtools__evaluate_script`. They must:

- Use **arrow function format**: `() => { ... }` or `async () => { ... }` (not IIFEs)
- Use **native property descriptors** for form updates (React/framework compatibility):
  ```js
  const nativeSetter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype, 'value'
  ).set;
  nativeSetter.call(input, value);
  input.dispatchEvent(new Event('input', { bubbles: true }));
  ```
- Return structured JSON objects with results and error details
- Configure behavior through constants at the top of the script (e.g., `PROJECTS_TO_DISCOVER`, `DAY_INDEX`, `ENTRIES`)

### FreshBooks API Integration

`freshbooks-api.sh` is a full REST API wrapper with:
- OAuth2 token auto-refresh (5-minute expiry buffer)
- 1Password credential reference support (`op read` integration)
- Cached business/account IDs at `~/.config/freshbooks/cache.json`
- Commands: `projects`, `clients`, `project-id`, `client-id`, `create-time-entry`, `list-time-entries`

### GitHub Activity Correlation

`fetch-github-activity.sh` uses `gh` CLI to pull PRs authored, reviewed, and events for a given date. The intervals-time-entry skill uses this to enrich time entry descriptions with PR context and learn repo→project mappings.

### Outlook Calendar Correlation

`fetch-outlook-calendar.sh` uses the Microsoft Graph API to fetch calendar events for a given date. OAuth tokens are stored at `~/.config/outlook/` with auto-refresh. One-time setup via `outlook-oauth.sh` (register an Azure AD app with `Calendars.Read` permission). The skill uses calendar data to:

- **Detect missing time entries** — meetings in the calendar with no corresponding notes entry
- **Validate durations** — flag discrepancies between notes and actual calendar event times
- **Enhance descriptions** — use meeting subjects, attendees, and body previews to replace vague notes like "meeting" with specific details
- **Time gap analysis** — combine calendar events with GitHub commit timestamps to reconstruct the full workday and identify unaccounted blocks
- **Learn mappings** — auto-populate `outlook-mappings.md` with recurring meeting→project associations (inferred from subjects, attendees via `people-context.md`, or user confirmation)

## Plugin Distribution

Plugin metadata lives in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`. Install with:
```bash
claude plugin install intervals-time-entry@olivoil
```

## Dependencies

- Chrome/Chromium with `--remote-debugging-port=9222` and chrome-devtools MCP server
- `gh` CLI (authenticated) for GitHub activity fetching
- `curl` and `jq` for FreshBooks and Microsoft Graph API calls
- (Optional) `op` CLI for 1Password credential references
- (Optional) Azure AD app registration for Outlook calendar integration (`~/.config/outlook/credentials.json`)
