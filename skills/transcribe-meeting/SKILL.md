---
name: transcribe-meeting
description: Transcribe a meeting recording from the Rodecaster SD card, Google Drive, or a local file. Creates a meeting note with summary, decisions, and action items, plus an MP3 archive. Use when the user types /transcribe-meeting or asks to transcribe a recording.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(echo $*), Bash(bash skills/transcribe-meeting/*), Bash(ffmpeg *), Bash(ffprobe *), Bash(curl *), Bash(gdown *), Bash(op read*), Bash(whisper* *), Bash(jq *), Bash(file *), Bash(stat *), Bash(ls /tmp/meeting*), Bash(ls /run/media/*), Task
---

# Transcribe Meeting

Transcribe a meeting recording and create a structured meeting note in the Obsidian vault with summary, decisions, action items, and full transcript.

Input sources (checked in order):
1. **SD card auto-detect** — Rodecaster recordings for the target date
2. **Google Drive URL** — if provided as argument
3. **Local file path** — if provided as argument

## Workflow

### Phase 0: Setup

1. Run `echo $OBSIDIAN_VAULT_PATH` to get the vault root. If empty, ask the user for the path.
2. Determine the target date: use the argument if a date is provided, otherwise use today.
3. Determine context: if the user provides additional info (project name, participants, meeting topic), note it. Otherwise, these will be inferred from any surrounding daily note context or left generic.

### Phase 1: Acquire Audio

Try sources in order:

**Option A: SD Card Auto-Detect (Primary)**

If no explicit URL or file path was given:

1. Run the discovery script:
   ```bash
   bash skills/transcribe-meeting/scripts/find-recordings.sh "{date}"
   ```
2. If recordings are found, check idempotency — for each recording, search for an existing meeting note:
   ```
   grep -rl 'recording: "{folder}"' "$VAULT/🎙️ Meetings/"
   ```
   Skip any recording that already has a meeting note.
3. If multiple new recordings exist, present them to the user and ask which to transcribe.
4. The audio file is the `path` from the JSON output.

**Option B: Google Drive URL**

If the input contains `drive.google.com`:

1. Run the download script:
   ```bash
   bash skills/transcribe-meeting/scripts/download-gdrive.sh "<url>"
   ```
2. Capture the output — it's the local file path.
3. Check idempotency via `audio_url` field (see Idempotency section).

**Option C: Local File Path**

If the input is a local file path, use it directly.

### Phase 2: Transcribe

1. Determine the engine: check `echo $OBSIDIAN_WHISPER_ENGINE` — defaults to `openai` if unset.
2. Run the transcription script:
   ```bash
   bash skills/transcribe-meeting/scripts/transcribe.sh "<audio-file>" "<engine>"
   ```
3. Capture the JSON output — an array of `{start, end, text}` segments.

### Phase 3: Summarize & Create Meeting Note

Using the transcript segments, generate:

1. **Title**: A concise meeting title (inferred from transcript content and any provided context)
2. **Summary**: 2-3 paragraph overview of what was discussed
3. **Decisions**: Key decisions made (bullet list, omit section if none)
4. **Action Items**: Tasks assigned with `@Name` attribution where possible (checklist, omit if none)
5. **Open Questions**: Unresolved items (bullet list, omit if none)

Format the transcript with timestamps:
```
[H:MM:SS] Text of the segment...
```

Create the meeting note at `$VAULT/🎙️ Meetings/{date} {Title}.md`:

```markdown
---
date: {YYYY-MM-DD}
project: "[[Project Name]]"
participants:
  - "[[Olivier]]"
recording: "{folder}"
audio_url: "{original-url-or-path}"
duration: {estimated-duration}
tags: [meeting]
---

# {Title}

## Summary
{2-3 paragraph summary}

## Decisions
- Decision 1
- Decision 2

## Action Items
- [ ] @Name: Task description
- [ ] @Name: Task description

## Open Questions
- Question 1

---

## Transcript

[0:00:12] First segment text...
[0:00:45] Next segment text...
```

Frontmatter notes:
- **SD card source**: set `recording: "{folder}"` (e.g., `recording: "9 - 18 Feb 2026"`). Set `audio_url` to the WAV path.
- **Google Drive source**: set `audio_url: "{url}"`. Omit `recording` field.
- **Local file source**: set `audio_url: "{path}"`. Omit `recording` field.

**Present the summary, decisions, and action items to the user for approval before writing the file.**

### Phase 4: Compress MP3 Archive

After the meeting note is created, compress the audio for archival:

```bash
bash skills/transcribe-meeting/scripts/compress.sh "<wav-file>"
```

Report the MP3 path to the user:
> MP3 archive saved to `/tmp/meeting-archive/Stereo Mix.mp3` (32MB) — upload to Google Drive at your convenience.

Skip this step if the source was already an MP3 or a Google Drive URL.

### Phase 5: Link from Daily Note (if applicable)

If a date is known (today by default), check if a daily note exists at `$VAULT/📅 Daily Notes/{date}.md`.

If the daily note contains the Google Drive URL that was transcribed:
- Replace the `[recording](url)` link with a wikilink to the meeting note: `[[{date} {Title}]]`

If the source was an SD card recording:
- Find the matching time entry line (by time proximity or project match) and append: ` - [[{date} {Title}]]`

If the daily note doesn't reference this recording but exists:
- Optionally add a reference under the appropriate project section

### Phase 6: Link from Project Note (if applicable)

If a project was identified, check if the project note exists in `$VAULT/🗂️ Projects/`.

If it exists, look for a `## Meetings` section:
- If found, append: `- [[{date} {Title}]]`
- If not found, add a `## Meetings` section with the link

## Timestamp Formatting

Convert seconds to `H:MM:SS` or `M:SS` format:
- Under 1 hour: `0:12`, `5:30`, `45:22`
- Over 1 hour: `1:05:30`, `2:15:00`

## Idempotency

Before creating a meeting note, check if one already exists:

**SD card source** — search by `recording` field:
```
grep -rl 'recording: "{folder}"' "$VAULT/🎙️ Meetings/"
```

**Google Drive / local source** — search by `audio_url` field:
```
grep -r "audio_url:" "$VAULT/🎙️ Meetings/" | grep "<url-or-path>"
```

If found, skip creation and return the existing note path.

## Error Handling

- If SD card not mounted: fall through to ask for URL or file path
- If `gdown` is not installed: tell the user to run `pip install gdown`
- If `ffmpeg` is not available: error with install instructions
- If OpenAI API key is missing: check 1Password, then ask user
- If transcription fails: report the error, suggest trying the other engine
