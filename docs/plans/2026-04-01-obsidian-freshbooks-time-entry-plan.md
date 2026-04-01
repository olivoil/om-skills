# obsidian-freshbooks-time-entry Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a skill that syncs Intervals time entries from SQLite to FreshBooks, faster than browser-based scraping.

**Architecture:** Single SKILL.md file with detailed instructions. Reuses `freshbooks-api.sh` and `project-mappings.md` from `intervals-to-freshbooks`. No new scripts needed.

**Tech Stack:** Claude Code skill (markdown), SQLite, FreshBooks API (via existing shell script), chrome-devtools MCP (browser refresh only)

---

### Task 1: Create the skill directory and SKILL.md

**Files:**
- Create: `skills/obsidian-freshbooks-time-entry/SKILL.md`

**Step 1: Create the skill directory**

```bash
mkdir -p skills/obsidian-freshbooks-time-entry
```

**Step 2: Write SKILL.md**

Create `skills/obsidian-freshbooks-time-entry/SKILL.md` with:

- Frontmatter: name `obsidian-freshbooks-time-entry`, description about syncing Intervals SQLite data to FreshBooks, allowed-tools for `mcp__chrome-devtools__*`, `Bash`, `Read`, `Write`, `Edit`
- Workflow phases:
  1. **Read project mappings** from `intervals-to-freshbooks/references/project-mappings.md`
  2. **Query SQLite for gaps** -- aggregate `intervals_time_entries` by date + mapped FB project, LEFT JOIN against `freshbooks_time_entries`, find rows where FB has no match
  3. **Display gaps** as a table and ask for confirmation
  4. **Create FreshBooks entries** via `intervals-to-freshbooks/scripts/freshbooks-api.sh`
  5. **Persist to SQLite** -- INSERT into `freshbooks_time_entries`
  6. **Update daily notes** -- append `### FreshBooks` section
  7. **Refresh FreshBooks browser tab**
- Include the exact SQL query for gap detection
- Include the mapping logic (Intervals project name contains the mapping key, strip SOW numbers)
- Reference exact paths relative to the plugin base directory using `../intervals-to-freshbooks/`

**Step 3: Commit**

```bash
git add skills/obsidian-freshbooks-time-entry/SKILL.md
git commit -m "feat: add obsidian-freshbooks-time-entry skill

SQLite-based sync from Intervals to FreshBooks. Reads local
intervals_time_entries table, compares against freshbooks_time_entries,
and creates missing entries via the FreshBooks API. Faster than
browser-based intervals-to-freshbooks skill."
```

### Task 2: Bump plugin version

**Files:**
- Modify: `.claude-plugin/marketplace.json`

**Step 1: Bump version from 4.2.0 to 4.3.0**

In `.claude-plugin/marketplace.json`, change `"version": "4.2.0"` to `"version": "4.3.0"`.

**Step 2: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "chore: bump om plugin version to 4.3.0"
```

### Task 3: Push and update installed plugin

**Step 1: Push to remote**

```bash
git push origin main
```

**Step 2: Update the installed plugin**

```bash
claude plugin marketplace update om
```

### Task 4: Verify the skill works

**Step 1: Test invocation**

Run `/obsidian-freshbooks-time-entry` in a conversation to verify it loads and detects gaps (or reports no gaps if fully synced).
