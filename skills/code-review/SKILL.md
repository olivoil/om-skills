---
name: code-review
description: Review a PR and post findings as inline comments to GitHub. Shows all feedback for approval before posting.
allowed-tools: Read, Glob, Grep, Bash(gh *), Bash(git *), Bash(bash skills/code-review/scripts/*)
---

# Code Review

Review a pull request, analyze changes with parallel specialized agents, and post findings as inline GitHub review comments after user confirmation.

## Phase 1: Resolve PR & Detect Re-review

Accept input as any of: PR URL, `#123`, a number, a branch name, or nothing (auto-detect current branch's PR).

**Resolve the PR number:**

```bash
# From URL: extract owner/repo and number from the URL
# From #123 or plain number:
gh pr view 123 --json number --jq '.number'
# From branch name:
gh pr view branch-name --json number --jq '.number'
# From nothing (current branch):
gh pr view --json number --jq '.number'
```

**Detect re-review:** Check if we already reviewed this PR.

```bash
# Get our GitHub username
gh api user --jq '.login'

# Fetch all reviews on this PR
gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '.[] | {id, user: .user.login, commit_id: .commit_id, state: .state}'
```

If a previous review from our user exists:
- Record the `commit_id` from our most recent review
- Fetch comments from that review: `gh api repos/{owner}/{repo}/pulls/{number}/reviews/{review_id}/comments`
- This is now a **re-review** — Phase 3 will diff against the previous review

## Phase 2: Fetch PR Context

Gather everything needed for the review:

```bash
# 1. PR metadata
gh pr view {number} --json number,title,body,author,baseRefName,headRefName,headRefOid,files,additions,deletions,url

# 2. Full diff
gh pr diff {number}

# 3. Changed files list
gh pr view {number} --json files --jq '.files[].path'
```

Then read:
- Root `CLAUDE.md` if it exists
- Any `CLAUDE.md` in directories containing changed files

**If re-review**, also identify what changed since last review:

```bash
gh api repos/{owner}/{repo}/compare/{last_reviewed_sha}...{current_head_sha} --jq '.files[].filename'
```

Finally, launch a **Haiku agent** to produce a 2-3 sentence summary of the PR's purpose from the diff and PR body. This summary is provided to each review agent for context.

## Phase 3: Analyze Changes (Multi-Agent)

Launch **7 parallel agents** via the Task tool (`subagent_type: "general-purpose"`). Provide each agent with:
- The full PR diff
- CLAUDE.md contents (root + directory-level)
- The PR summary from Phase 2
- The list of changed files

Each agent focuses on one review dimension. Instruct each to return a JSON array of issues.

### General Review Agents

| # | Model | Focus | Instructions |
|---|-------|-------|-------------|
| 1 | Sonnet | **CLAUDE.md compliance** | Audit changes against project conventions in CLAUDE.md. Only flag violations of rules explicitly stated in CLAUDE.md. If no CLAUDE.md exists, return an empty array. |
| 2 | Sonnet | **Bug detection** | Shallow scan of the diff for obvious bugs: logic errors, off-by-one, null/undefined risks, race conditions, resource leaks. Avoid stylistic nitpicks. |
| 3 | Sonnet | **Git history context** | Run `git log` and `git blame` on modified files. Identify bugs or regressions only visible with historical knowledge (e.g., reverted fixes, violated assumptions from past commits). |
| 4 | Haiku | **Previous PR comments** | Use `gh pr list --state merged --search` to find previous PRs that touched these files. Check their review comments for patterns that may apply here too. |
| 5 | Haiku | **Code comment compliance** | Read the full source files (not just the diff) for inline comments: `// TODO`, `// IMPORTANT`, `// NOTE`, `// HACK`, `// FIXME`. Ensure changes respect these annotations. |

### Specialized Review Agents

| # | Model | Focus | Instructions |
|---|-------|-------|-------------|
| 6 | Sonnet | **Security** | OWASP top 10: injection (SQL, command, XSS), auth bypass, credential exposure, insecure deserialization, SSRF, path traversal. Check for hardcoded secrets, unsafe `eval`, unvalidated redirects, missing input sanitization. |
| 7 | Sonnet | **Error handling** | Empty catch blocks, swallowed errors, broad exception handling (`catch(e) {}`), missing error propagation, fallback behavior that hides real problems. Ensure callers get actionable feedback on failures. |
| 8 | Sonnet | **Performance** | N+1 queries, unnecessary re-renders, memory leaks, O(n²) where O(n) is possible, large/unnecessary imports, missing pagination, unbounded loops or allocations. |

**Each agent must return issues in this exact JSON format:**

```json
[
  {
    "path": "src/app.js",
    "line": 42,
    "severity": "critical",
    "body": "Markdown explanation of the issue with a suggested fix",
    "category": "bug"
  }
]
```

Where:
- `path` — file path relative to repo root
- `line` — line number in the new version of the file (from the diff's `+` side)
- `severity` — one of `critical`, `important`, `suggestion`
- `body` — markdown explanation, including a fix suggestion when possible
- `category` — one of `claude-md`, `bug`, `history`, `previous-pr`, `code-comment`, `security`, `error-handling`, `performance`

## Phase 4: Score & Filter

Collect all issues from the 9 agents. Deduplicate issues that flag the same line with the same concern.

For each unique issue, launch a **parallel Haiku agent** (`model: "haiku"`) that independently scores confidence (0–100):

- **0** — False positive, doesn't survive scrutiny, or the issue is pre-existing (not introduced by this PR)
- **25** — Might be real, might be false positive. Stylistic preference not backed by CLAUDE.md
- **50** — Real but minor nitpick, low practical impact
- **75** — Very likely real, will impact functionality, or directly violates a CLAUDE.md rule
- **100** — Confirmed real, will happen frequently, evidence is clear in the diff

Provide each scoring agent with:
- The issue object (path, line, severity, body, category)
- The relevant diff hunk (±10 lines around the flagged line)
- CLAUDE.md contents (for `claude-md` category issues, the agent must verify the specific rule exists)

**Filter rules** — discard issues that:
- Score below **80**
- Flag lines the PR author didn't modify (pre-existing issues)
- Would be caught by a linter or type checker (eslint, tsc, mypy, etc.)
- Describe intentional behavior changes that match the PR's stated purpose
- Are silenced by lint-ignore comments (`// eslint-disable`, `# noqa`, etc.)

## Phase 5: Re-review Delta

**Skip this phase if this is a first review.**

If this is a re-review (previous review detected in Phase 1), categorize surviving issues:

1. **Addressed** — issues from our previous review that no longer appear (author fixed them)
2. **Still outstanding** — issues from our previous review that remain unfixed (match by file path + similar body text)
3. **New issues** — issues on code that changed since our last review commit

Build a delta summary for inclusion in the review body.

## Phase 6: Preview & Confirm

Present all surviving findings to the user, grouped by severity.

**First-review format:**

```
## Code Review: {owner}/{repo}#{number}
**{title}** | Author: {author} | Changes: +{additions} -{deletions} across {N} files

### Critical ({count})
- **src/app.js:42** — [Bug] Description (confidence: 92)

### Important ({count})
- **src/utils.ts:15** — [CLAUDE.md] Description (confidence: 85)

### Suggestions ({count})
- **src/helper.js:88** — [Performance] Description (confidence: 80)

**Summary:** 1-2 sentence overall assessment of the PR.
```

**Re-review format** — additionally show before the summary:

```
### Since Last Review
- {N} issues addressed (fixed by author)
- {N} issues still outstanding
- {N} new issues found
```

Then ask the user to choose how to post the review:

1. **Pending** — draft review, only visible to PR author (default for first review)
2. **Comment** — visible review, no approve/reject
3. **Approve** — approve the PR
4. **Request changes** — block the PR
5. **Cancel** — don't post anything

If there are zero issues after filtering, still allow the user to post an approval with a clean summary.

## Phase 7: Post Review

If the user chose Cancel, stop here.

Otherwise, write the comments array to a temporary JSON file and run:

```bash
bash skills/code-review/scripts/post-github-review.sh \
  --owner "{owner}" \
  --repo "{repo}" \
  --pr {number} \
  --commit "{head_sha}" \
  --event "{PENDING|APPROVE|REQUEST_CHANGES|COMMENT}" \
  --body "Review summary text" \
  --comments /tmp/review-comments-{number}.json
```

Use `--event PENDING` for draft reviews (this is also the default if `--event` is omitted).

The comments JSON file format:

```json
[
  {
    "path": "src/app.js",
    "line": 42,
    "body": "**[Bug]** Markdown explanation with fix suggestion"
  }
]
```

Clean up the temporary JSON file after posting.

## Phase 8: Confirm

Report success to the user:

```
Review posted: {review_url}
{N} inline comments + summary on {owner}/{repo}#{number}
```

If re-review, also mention:
```
Delta: {N} addressed, {N} outstanding, {N} new
```
