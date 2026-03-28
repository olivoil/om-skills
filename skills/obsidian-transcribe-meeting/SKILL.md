---
name: obsidian-transcribe-meeting
description: Transcribe a meeting recording from the Rodecaster SD card, Google Drive, or a local file. Creates a meeting note with summary, decisions, and action items, plus an MP3 archive. Use when the user types /transcribe-meeting or asks to transcribe a recording.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(obsidian *), Bash(bash *obsidian-transcribe-meeting/scripts/*), Bash(*bash *obsidian-transcribe-meeting/scripts/*), Bash(ffmpeg *), Bash(ffprobe *), Bash(curl *), Bash(gdown *), Bash(rclone *), Bash(op read*), Bash(whisper* *), Bash(python3 *), Bash(jq *), Bash(file *), Bash(stat *), Bash(ls *), Bash(youtubeuploader *), Bash(bc *), Bash(udisksctl *), Bash(lsblk *), Bash(md5sum *), Bash(date *), Bash(grep *), Bash(cat *), Bash(echo *), Bash(mkdir *)
---

# Transcribe Meeting

Transcribe a meeting recording and create a structured meeting note in the Obsidian vault with summary, decisions, action items, and full transcript.

Input sources (checked in order):
1. **Auto-detect** — Screen recordings + Rodecaster recordings for the target date (matched by time overlap)
2. **Google Drive URL** — if provided as argument
3. **Local file path** — if provided as argument

Recording modes:
- **omarchy+rodecaster** — screen recording + Rodecaster WAV matched by start time. Transcribe from Rodecaster (better audio). Upload merged video (Rodecaster audio + screen video) to YouTube + MP3 to Google Drive.
- **omarchy-only** — screen recording with no matching Rodecaster. Extract audio from MP4 for transcription. Upload original MP4 to YouTube.
- **rodecaster-only** — Rodecaster recording with no matching screen recording. Upload MP3 to Google Drive only (existing behavior).

## Workflow

### Phase 0: Setup

1. Run `obsidian vault info=path` to get the vault root.
2. Determine the target date: use the argument if a date is provided, otherwise use today.
3. Determine context: if the user provides additional info (project name, participants, meeting topic), note it. Otherwise, these will be inferred from any surrounding daily note context or left generic.

### Phase 1: Discover & Match Recordings

Try sources in order:

**Option A: Auto-Detect (Primary)**

If no explicit URL or file path was given:

1. **Discover screen recordings**:
   ```bash
   bash skills/obsidian-transcribe-meeting/scripts/find-screenrecordings.sh "{date}"
   ```
   Save the JSON output to a temp file (e.g., `/tmp/screenrecs-{date}.json`).

2. **Discover Rodecaster recordings**:
   ```bash
   RODECASTER_MOUNT=/run/media/olivier/RodeCaster/RODECaster bash skills/obsidian-transcribe-meeting/scripts/find-recordings.sh "{date}"
   ```
   If `RODECASTER_MOUNT` fails (directory not found), fall back without it to try auto-detect.
   Save the JSON output to a temp file (e.g., `/tmp/rodecaster-{date}.json`).

3. **Match recordings** by time overlap:
   ```bash
   bash skills/obsidian-transcribe-meeting/scripts/match-recordings.sh /tmp/screenrecs-{date}.json /tmp/rodecaster-{date}.json
   ```
   This produces groups with `mode` (omarchy+rodecaster, omarchy-only, rodecaster-only), `video`, `audio`, and `transcribe_from` fields.

4. **Check idempotency** — for each group, search for existing meeting notes:
   - By `recording:` field (for groups with Rodecaster audio):
     ```
     obsidian search query='recording: "{folder}"' path=Meetings
     ```
   - By `video_file:` field (for groups with screen recordings):
     ```
     obsidian search query='video_file: "{filename}"' path=Meetings
     ```
   Skip any group that already has a meeting note.

5. **Present findings** to the user with mode info for each group:
   > Found 2 recording groups:
   > 1. **omarchy-only**: screen recording from 09:36 (30 min) — no matching Rodecaster
   > 2. **omarchy+rodecaster**: screen recording from 11:02 (51 min) + Rodecaster recording 10 (51 min)

6. **Determine audio source** for transcription:
   - `omarchy+rodecaster` → audio = Rodecaster WAV (the `audio.path` field)
   - `omarchy-only` → extract audio from screen recording:
     ```bash
     bash skills/obsidian-transcribe-meeting/scripts/extract-audio.sh "{video.path}"
     ```
     Capture the WAV path from stdout.
   - `rodecaster-only` → audio = Rodecaster WAV (the `audio.path` field)

**Option B: Google Drive URL**

If the input contains `drive.google.com`:

1. Run the download script:
   ```bash
   bash skills/obsidian-transcribe-meeting/scripts/download-gdrive.sh "<url>"
   ```
2. Capture the output — it's the local file path.
3. Check idempotency via `audio_url` field (see Idempotency section).

**Option C: Local File Path**

If the input is a local file path, use it directly.

### Phase 2: Transcribe

1. Determine the engine: check `echo $OBSIDIAN_WHISPER_ENGINE` — defaults to `openai` if unset.
2. Run the transcription script:
   ```bash
   bash skills/obsidian-transcribe-meeting/scripts/transcribe.sh "<audio-file>" "<engine>"
   ```
3. Capture the JSON output — an array of `{start, end, text}` segments.
   - With pyannote VAD: segments also include `speaker` field (e.g. `"SPEAKER_00"`)

**VAD (Voice Activity Detection)** is controlled by `OBSIDIAN_VAD_MODEL`:
- `none` (default) — no VAD, uses silence trimming + fixed chunking (current behavior)
- `silero` — Silero VAD strips non-speech segments before transcription. Fast, CPU-only. Reduces Whisper hallucination and improves chunking.
- `pyannote` — pyannote.audio speaker diarization. Provides VAD + speaker labels so the transcript is attributed per-speaker. Requires GPU (ROCm/CUDA) and `HF_TOKEN` for HuggingFace model access.

When VAD provides speaker labels (pyannote mode), Phase 3 should use them to attribute speech in the transcript and improve summarization (decisions, action items attributed to specific speakers).

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

When speaker labels are present (pyannote mode), format as:
```
[H:MM:SS] **Speaker A**: Text of the segment...
[H:MM:SS] **Speaker B**: Text of the segment...
```
Speaker labels from pyannote are generic (`SPEAKER_00`, `SPEAKER_01`). Replace with real names if participants are known from context, daily notes, or `people-context.md`. Otherwise use `Speaker A`, `Speaker B`, etc.

Create the meeting note with `obsidian create path="Meetings/{date} {Title}.md" content="{formatted content}"`:

```markdown
---
date: {YYYY-MM-DD}
project: "[[Project Name]]"
participants:
  - "[[Olivier]]"
recording: "{folder}"
audio_url: "{original-url-or-path}"
video_file: "{screenrecording-filename}"    # only if video exists, for idempotency
video_url: "{youtube-url}"                  # only after YouTube upload
recording_mode: "{omarchy+rodecaster|omarchy-only|rodecaster-only}"  # informational
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
- **omarchy+rodecaster**: set `recording: "{folder}"`, `video_file: "{filename}"`, `recording_mode: "omarchy+rodecaster"`. Set `audio_url` to the WAV path initially — Phase 4 will replace it with the Google Drive URL after upload. Set `video_url` after YouTube upload.
- **omarchy-only**: set `video_file: "{filename}"`, `recording_mode: "omarchy-only"`. Set `audio_url` to the extracted WAV path initially. Set `video_url` after YouTube upload.
- **rodecaster-only**: set `recording: "{folder}"`, `recording_mode: "rodecaster-only"`. Set `audio_url` to the WAV path initially — Phase 4 will replace it with the Google Drive URL after upload. Omit `video_file` and `video_url`.
- **Google Drive source**: set `audio_url: "{url}"`. Omit `recording`, `video_file`, `video_url` fields.
- **Local file source**: set `audio_url: "{path}"`. Omit `recording` field — Phase 4 will replace it with the Google Drive URL after upload.

**Present the summary, decisions, and action items to the user for approval before writing the file.**

### Phase 3.5: Extract Key Screenshots

Applies to **all recording modes** (omarchy+rodecaster, omarchy-only, and rodecaster-only).

**Step 1 — Find user screenshots taken during the meeting**:
```bash
bash skills/obsidian-transcribe-meeting/scripts/find-screenshots.sh "{date}" "{start_time}" "{duration_secs}"
```
This returns a JSON array of screenshots from `~/Pictures/` (or `$OMARCHY_SCREENSHOT_DIR` / `$XDG_PICTURES_DIR`) taken during the meeting timeframe (±5 min buffer). Each entry has `path`, `timestamp`, and `offset_secs`. This script has no video dependency — it matches screenshot timestamps against the meeting time window.

**Step 2 — Copy and embed user screenshots**:
For each found screenshot:
- Copy to `$VAULT/Attachments/{meeting-name}-user-{HH-MM-SS}.png`
- Place in the meeting note at the transcript position closest to its `offset_secs`
- Embed using `![[filename.png]]`

**Step 3 — Supplement with ffmpeg-extracted frames** (only when video exists):
This step only applies to `omarchy+rodecaster` and `omarchy-only` modes. Skip entirely for `rodecaster-only`.
- If fewer than 3 user screenshots were found, scan the transcript for visual moments (screen sharing, demos, "as you can see", "look at this", code references, topic transitions) and extract additional frames to reach 3-8 total:
  ```bash
  ffmpeg -ss {secs} -i "{video}" -frames:v 1 -q:v 2 -y "$VAULT/Attachments/{name}-{MM-SS}.png"
  ```
- If 3+ user screenshots were found, skip ffmpeg extraction entirely.

Embed all screenshots at corresponding transcript positions using `![[filename.png]]`.

### Phase 4: Post-Process & Upload

After the meeting note is created, compress audio, merge video if applicable, and upload:

**4a. Compress WAV → MP3** (all modes with audio):
```bash
bash skills/obsidian-transcribe-meeting/scripts/compress.sh "<wav-file>"
```

**4b. Upload MP3 to Google Drive** (all modes with audio):
```bash
bash skills/obsidian-transcribe-meeting/scripts/upload-gdrive.sh "<mp3-file>"
```
Capture the Google Drive URL from stdout. Update `audio_url` in the meeting note frontmatter.

**4c. Merge video + Rodecaster audio** (omarchy+rodecaster mode only):
```bash
bash skills/obsidian-transcribe-meeting/scripts/merge-av.sh "<video-file>" "<rodecaster-wav>"
```
Capture the merged MP4 path from stdout. This replaces the screen recording's audio with the higher-quality Rodecaster audio.

**4d. Upload video to YouTube** (omarchy+rodecaster and omarchy-only modes):
```bash
bash skills/obsidian-transcribe-meeting/scripts/upload-youtube.sh "<video-file>" "<meeting-title>" "<summary>" "<date>"
```
- For `omarchy+rodecaster`: upload the **merged** MP4 (from step 4c)
- For `omarchy-only`: upload the **original** screen recording MP4
- Capture the YouTube URL from stdout.

**4e. Update meeting note frontmatter**:
- Set `audio_url` to the Google Drive URL (from step 4b)
- Set `video_url` to the YouTube URL (from step 4d, if applicable)

Skip this phase if the source was already a Google Drive URL.

### Phase 5: Link from Daily Note (if applicable)

If a date is known (today by default), run `obsidian daily:read` to check if a daily note exists.

If the daily note contains the Google Drive URL that was transcribed:
- Replace the `[recording](url)` link with a wikilink to the meeting note: `[[{date} {Title}]]`

If the source was an SD card recording:
- Find the matching time entry line (by time proximity or project match) and append: ` - [[{date} {Title}]]`

If the daily note doesn't reference this recording but exists:
- Optionally add a reference under the appropriate project section

### Phase 6: Link from Project Note (if applicable)

If a project was identified, check if the project note exists in `$VAULT/Projects/`.

If it exists, look for a `## Meetings` section:
- If found, use `obsidian append path="Projects/{project}.md" content="- [[{date} {Title}]]"` to add the link
- If not found, use `Read` + `Edit` to add a `## Meetings` section with the link

## Timestamp Formatting

Convert seconds to `H:MM:SS` or `M:SS` format:
- Under 1 hour: `0:12`, `5:30`, `45:22`
- Over 1 hour: `1:05:30`, `2:15:00`

## Idempotency

Before creating a meeting note, check if one already exists:

**Rodecaster source** — search by `recording` field:
```
obsidian search query='recording: "{folder}"' path=Meetings
```

**Screen recording source** — search by `video_file` field:
```
obsidian search query='video_file: "{filename}"' path=Meetings
```

**Google Drive / local source** — search by `audio_url` field:
```
obsidian search query='audio_url: "{url-or-path}"' path=Meetings
```

If any search returns results, skip creation and return the existing note path. A group is considered already processed if **either** its `recording` folder or `video_file` filename matches an existing note.

## Error Handling

- If SD card not mounted: fall through to ask for URL or file path
- If `gdown` is not installed: tell the user to run `pip install gdown`
- If `ffmpeg` is not available: error with install instructions
- If OpenAI API key is missing: check 1Password, then ask user
- If transcription fails: report the error, suggest trying the other engine
- If VAD fails: falls back automatically to default chunking (no VAD), warns the user
- If pyannote fails due to missing `HF_TOKEN`: tell user to set `HF_TOKEN` and accept model terms at huggingface.co/pyannote/speaker-diarization-3.1
