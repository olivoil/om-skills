---
name: intervals-time-entry
description: Fill Intervals Online time entries from daily notes. Use when asked to fill time entries, timesheets, or submit hours to Intervals. Requires chrome-devtools MCP with browser open to Intervals.
allowed-tools: mcp__chrome-devtools__*, Bash(op read*), Bash(gh *), Bash(bash .claude/intervals-cache/*.sh *), Read, Write, Edit
---

# Intervals Time Entry Automation

Fill time entries in Intervals Online from Obsidian daily notes using MCP chrome-devtools.

## Prerequisites

1. Chrome/Chromium running with `--remote-debugging-port=9222`
2. Intervals page open: `https://bhi.intervalsonline.com/time/multiple/`
3. chrome-devtools MCP server configured

## Cache Location

**IMPORTANT**: Cached files are stored in the PROJECT, not the plugin:

```
<project-root>/.claude/intervals-cache/
├── project-mappings.md      # Project→workType mappings
├── github-mappings.md       # Repo→project mappings
└── fetch-github-activity.sh # GitHub activity fetcher script
```

These files persist between sessions. If they don't exist, create them from the plugin's `references/` and `scripts/` directories.

## Workflow

### Phase 1: Read Notes

Read the daily note for the requested date. Default location: `📅 Daily Notes/YYYY-MM-DD.md`

Look for:
- Time entries with project/work descriptions
- Links to GitHub PRs or repos (e.g., `https://github.com/owner/repo/pull/123`)
- Mentions of PR numbers (e.g., "PR #123", "reviewed PR 456")

### Phase 1.5: GitHub Activity Correlation (REQUIRED)

**ALWAYS run this phase** to fetch GitHub activity and enhance time entry descriptions.

#### Step 1: Ensure Script Is Up-to-Date

The script has a version number on line 2 (e.g., `# Version: 2`). Check and update if needed:

1. Read the plugin script: `~/.claude/skills/intervals-time-entry/scripts/fetch-github-activity.sh`
2. Extract the version number from line 2
3. If `.claude/intervals-cache/fetch-github-activity.sh` exists, extract its version number
4. If the cached script doesn't exist OR the plugin version is higher, copy the plugin script to `.claude/intervals-cache/fetch-github-activity.sh`

This ensures users always have the latest script with bug fixes and new features.

#### Step 2: Fetch Activity

**Run this command** (replace YYYY-MM-DD with the target date):
```bash
bash .claude/intervals-cache/fetch-github-activity.sh YYYY-MM-DD
```

This returns JSON with:
- PRs authored (created or updated)
- PRs reviewed
- Events with timestamps (commits, reviews, comments)

#### Step 3: Correlate with Notes

Using the JSON output from Step 2:
1. **Match PRs to time entries**: If notes mention a PR or repo, link it to that entry
2. **Infer repo→project mappings**: When a PR clearly matches a time entry's project, add to `.claude/intervals-cache/github-mappings.md`
3. **Extract PR links from notes**: Look for GitHub URLs and extract repo/PR info

#### Step 4: Enhance Descriptions

**ALWAYS improve descriptions** when GitHub data provides more context. The goal is to make time entries self-documenting and meaningful for future reference.

**Before/After Examples:**

| Notes say | GitHub shows | Final description |
|-----------|--------------|-------------------|
| "font awesome icon PR" | PR #574: "Add FontAwesome Pro icons to design system" | Add FontAwesome Pro icons to design system (PR #574) |
| "review and merge PRs" | Reviewed PR #580, #581, #583 | Code review: notification preferences (#580), cart validation (#581), search filters (#583) |
| "text-transform work" | PR #579: "Add text-transform utilities to typography tokens" | Add text-transform utilities to typography design tokens (PR #579) |
| "bug fixes" | PR #602: "Fix race condition in checkout flow" | Fix race condition in checkout flow (PR #602) |
| "API work" | Commits: "Add pagination to /users endpoint", "Handle empty results" | Add pagination to /users endpoint with empty result handling |

**Rules:**
- Use the PR title as the primary description when available (it's usually well-written)
- Use the PR description/body for additional context when the title alone is too brief or generic
- Add PR number in parentheses at the end: `(PR #123)`
- For reviews, briefly describe each PR reviewed (2-5 words each)
- For commits without PRs, summarize the commit messages
- Keep to 1-2 sentences max, but make them specific and meaningful
- Never use generic descriptions like "development work" when GitHub has specifics

#### Step 5: Suggest Adjustments

Compare GitHub activity to notes and flag potential issues:

**Missing time entries**: If GitHub shows significant activity (multiple commits, PRs) for a repo but notes have no corresponding entry, suggest adding one.

**Time discrepancies**: Use commit timestamps to estimate minimum time spent:
- Calculate span from first to last commit on a repo
- Account for gaps >2h as breaks
- If notes show significantly less time than commits suggest, flag for review

Example output:
```
⚠️ GitHub shows commits on technomic-api from 9:15am to 3:30pm (~4-5h with breaks)
   but notes only show 2h for Technomic dev work. Consider adjusting.

💡 Found PR #456 "Fix payment edge case" for Technomic - using for description.

📝 No time entry found for 3 PR reviews on ewg-frontend. Suggest adding:
   - EWG: 0.5-1h Architecture/Technical Design (PR reviews #12, #13, #14)
```

### Phase 2: Load Mappings

1. **Read project cache**: `.claude/intervals-cache/project-mappings.md` (in the project root)
2. **Read GitHub mappings cache**: `.claude/intervals-cache/github-mappings.md` (learned repo→project associations)
3. **Read plugin references** for defaults: `references/worktype-mappings.md`, `references/people-context.md`

If the project cache doesn't exist, create it by copying from `references/project-mappings.md`.
If the GitHub mappings cache doesn't exist, create it from `references/github-mappings.md`.

Output format: `Project | Work Type | Hours | Description`

### Phase 3: Validate Against Cache

Check the project cache for work types:
- If all projects have cached work types → skip browser inspection
- If any project is NOT cached → inspect browser to discover its work types

### Phase 4: Browser Automation

#### Step 1: Find or Create Intervals Tab

**IMPORTANT**: Never navigate away from the user's current tab. Always find an existing Intervals tab or create a new one.

1. Call `list_pages` to see all open browser tabs
2. Look for a tab with URL containing `intervalsonline.com`
3. If found: call `select_page` with that page's ID
4. If NOT found: call `new_page` with URL `https://bhi.intervalsonline.com/time/multiple/`
5. Only call `navigate_page` if the selected tab is on Intervals but wrong URL (e.g., different week)

#### Step 2: Run Scripts

Use MCP chrome-devtools with these scripts from `scripts/`:

1. **Basic inspection** (`scripts/inspect-basics.js`): Get dates and day index
2. **Discover work types** (`scripts/discover-worktypes.js`): For uncached projects only
3. **Fill entries** (`scripts/fill-entries.js`): Fill all validated entries

**IMPORTANT**: All scripts use arrow function format for MCP compatibility:
```javascript
// ✅ Correct
async () => { ... }

// ❌ Wrong - causes syntax errors
(async function() { ... })();
```

### Phase 5: UPDATE THE CACHE (Critical!)

**After discovering new work types, ALWAYS update the project cache file.**

If you discovered work types for a new project (e.g., "Drees Maintenance and Support"):

1. Read the current cache: `.claude/intervals-cache/project-mappings.md`
2. Add the new project section:

```markdown
### Drees Maintenance and Support (20240034)
- Development - US
- Meeting: Client Meeting - US
- QA/Testing - US
```

3. Write the updated file back

**Example update workflow:**
```
1. Read .claude/intervals-cache/project-mappings.md
2. Append new section under "## Cached Work Types by Project"
3. Write updated content to .claude/intervals-cache/project-mappings.md
```

This ensures future runs skip inspection for this project, saving time and tokens.

### Phase 5.5: Update GitHub Mappings Cache

When you discover a new repo→project association (from PR links in notes or inferred from context):

1. Read the current cache: `.claude/intervals-cache/github-mappings.md`
2. Add the mapping to the table:

```markdown
| owner/repo-name | Intervals Project Name |
```

3. Write the updated file back

This helps future correlation work more accurately by remembering which repos belong to which projects.

### Phase 6: Verify

Take screenshot to confirm entries are correct.

## Quick Reference

### Day Index Mapping

| Day | Index |
|-----|-------|
| Sunday | 0 |
| Monday | 1 |
| Tuesday | 2 |
| Wednesday | 3 |
| Thursday | 4 |
| Friday | 5 |
| Saturday | 6 |

### Common Fallbacks

| Project | Missing Work Type | Use Instead |
|---------|-------------------|-------------|
| Meeting | Internal Working Session | Team/Company Meeting |
| EWG Feature Enhancement Addendum | Analysis - US | Development - US |

## Customization

### Plugin References (read-only defaults)
The `references/` files in this plugin contain default mappings. Fork this repo to customize for your organization.

### Project Cache (read-write, auto-updated)
The cache at `.claude/intervals-cache/project-mappings.md` in your project:
- Gets created automatically from plugin defaults on first run
- Gets UPDATED automatically when new projects are discovered
- Persists between sessions
- Is project-specific (each project can have its own cache)

### GitHub Mappings Cache (read-write, auto-learned)
The cache at `.claude/intervals-cache/github-mappings.md`:
- Gets created on first use from plugin template
- Gets UPDATED when Claude discovers repo→project associations from:
  - PR links in your notes (e.g., `https://github.com/acme/widget/pull/123`)
  - Contextual inference (PR activity matching time entry project names)
- Used to correlate future GitHub activity to correct Intervals projects

## First-Time Setup

On first use in a new project, Claude will:
1. Check if `.claude/intervals-cache/project-mappings.md` exists
2. If not, create it from the plugin's `references/project-mappings.md` template
3. Check if `.claude/intervals-cache/github-mappings.md` exists
4. If not, create it from the plugin's `references/github-mappings.md` template
5. Check if `.claude/intervals-cache/fetch-github-activity.sh` exists and compare version
6. If missing or outdated, copy from the plugin's `scripts/fetch-github-activity.sh`
7. Use and update these local caches going forward

## Efficiency

This skill is optimized for minimal browser interaction:
- **Cached mappings** eliminate redundant inspection
- **Auto-updating cache** means you only inspect each project ONCE ever
- **Single script execution** fills all entries
- **GitHub correlation** runs once via `gh` CLI, no browser needed
- **Learned repo mappings** improve correlation accuracy over time
