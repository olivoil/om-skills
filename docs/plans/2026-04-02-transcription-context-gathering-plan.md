# Transcription Context Gathering Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Gather participant names and project vocabulary before whisper runs, so transcriptions have better name spelling and meeting summaries have accurate action item attribution.

**Architecture:** Add a Phase 1.5 to the transcription skill that runs three parallel context-gathering tracks (screenshots, vault context, quick first-pass), combines them into a whisper prompt string, and passes participant info through to summarization. Modify `transcribe.sh` to accept a `WHISPER_PROMPT` env var. Update SKILL.md with the new phase and improved attribution guidance.

**Tech Stack:** bash, ffmpeg, whisper-cli/OpenAI API, Claude vision (for screenshot OCR)

---

### Task 1: Add WHISPER_PROMPT support to transcribe.sh

**Files:**
- Modify: `skills/obsidian-transcribe-meeting/scripts/transcribe.sh`

**Step 1: Update the script header comment**

Add `WHISPER_PROMPT` to the Environment section (line 17 area):

```bash
#   WHISPER_PROMPT       — optional initial prompt for whisper (names, terms for spelling)
```

**Step 2: Update transcribe_openai_chunk to pass prompt**

Change the function (lines 58-69) to:

```bash
transcribe_openai_chunk() {
    local chunk_file="$1"
    local api_key="$2"

    local prompt_args=()
    if [ -n "$WHISPER_PROMPT" ]; then
        prompt_args=(-F "prompt=$WHISPER_PROMPT")
    fi

    curl -s -X POST "https://api.openai.com/v1/audio/transcriptions" \
        -H "Authorization: Bearer ${api_key}" \
        -F "file=@${chunk_file}" \
        -F "model=whisper-1" \
        -F "response_format=verbose_json" \
        -F "timestamp_granularities[]=segment" \
        "${prompt_args[@]}" \
    | jq '.segments // [] | map({start, end, text})'
}
```

**Step 3: Update transcribe_local_chunk to pass prompt**

Change the function (lines 71-85) to:

```bash
transcribe_local_chunk() {
    local chunk_file="$1"
    local output_file="/tmp/whisper_output_$$"

    local prompt_args=()
    if [ -n "$WHISPER_PROMPT" ]; then
        prompt_args=(--prompt "$WHISPER_PROMPT")
    fi

    whisper-cli \
        --model /home/olivier/.local/share/pywhispercpp/models/ggml-large-v3.bin \
        --output-json \
        --output-file "$output_file" \
        --no-speech-thold 0.80 \
        "${prompt_args[@]}" \
        --file "$chunk_file" \
        >/dev/null 2>&1

    jq '.transcription // [] | map({start: .offsets.from, end: .offsets.to, text})' "${output_file}.json"
    rm -f "${output_file}.json"
}
```

**Step 4: Change default VAD model from none to silero**

Change line 101 from:
```bash
VAD_MODELS="${OBSIDIAN_VAD_MODEL:-none}"
```
to:
```bash
VAD_MODELS="${OBSIDIAN_VAD_MODEL:-silero}"
```

**Step 5: Commit**

```bash
git add skills/obsidian-transcribe-meeting/scripts/transcribe.sh
git commit -m "Add WHISPER_PROMPT support and default VAD to silero"
```

---

### Task 2: Add Phase 1.5 (Gather Context) to SKILL.md

**Files:**
- Modify: `skills/obsidian-transcribe-meeting/SKILL.md`

**Step 1: Insert Phase 1.5 after Phase 1 (after line 79)**

Add the following section between Phase 1 and Phase 2:

```markdown
### Phase 1.5: Gather Context

Before transcription, gather participant names and project vocabulary to improve whisper accuracy and action item attribution. Run the three tracks below **in parallel** to minimize added time.

**Track 1: Screenshots**

Find screenshots taken during the meeting window:
```bash
bash skills/obsidian-transcribe-meeting/scripts/find-screenshots.sh "{date}" "{start_time}" "{duration_secs}"
```
Save the JSON result for reuse in Phase 3.5. For each screenshot found, read the image and look for:
- Participant names visible in the Teams/Zoom/Meet UI (participant panel, name labels on video tiles)
- Any on-screen text that reveals the meeting title or topic

Collect all names found across all screenshots.

**Track 2: Vault context**

1. Read the daily note for the target date (`Daily Notes/{date}.md`)
2. From the time entry lines, identify which project this recording likely belongs to (match by time proximity to the recording start time)
3. If a project is identified, read the project page (`Projects/{project}.md`) and extract:
   - Team member names (from wikilinks like `[[Name]]` in any section)
   - Project-specific terminology (product names, acronyms, technical terms)
4. Also check if participants are mentioned in the time entry line itself (e.g., "sync with Bhrugen")

**Track 3: Quick first-pass**

1. Extract the first 90 seconds of audio:
   ```bash
   ffmpeg -i "{audio-file}" -t 90 -c:a pcm_s16le -ar 16000 -ac 1 /tmp/firstpass_$$.wav -y -loglevel warning
   ```
2. Transcribe just that clip (no prompt, fast since it's tiny):
   ```bash
   bash skills/obsidian-transcribe-meeting/scripts/transcribe.sh /tmp/firstpass_$$.wav "{engine}"
   ```
3. Scan the resulting text for proper nouns and name-like words
4. Clean up: `rm /tmp/firstpass_$$.wav`

**Combine results**

Merge and deduplicate names from all three tracks. Build the whisper prompt:
```
Meeting participants: Olivier, Kanish, Tara, Dinesh, Adam. Project: KHov. Topics: deployment pipelines, QA issues, container apps.
```

Store this as `WHISPER_PROMPT` for Phase 2 and keep the participant list for Phase 3.

If no context was gathered from any track (no screenshots, no daily note match, no names in first-pass), proceed without a prompt. This is not an error.
```

**Step 2: Commit**

```bash
git add skills/obsidian-transcribe-meeting/SKILL.md
git commit -m "Add Phase 1.5: pre-transcription context gathering"
```

---

### Task 3: Update Phase 2 in SKILL.md to use WHISPER_PROMPT

**Files:**
- Modify: `skills/obsidian-transcribe-meeting/SKILL.md`

**Step 1: Update the Phase 2 transcribe command (line 99-102 area)**

Replace the Phase 2 section with:

```markdown
### Phase 2: Transcribe

1. Determine the engine: check `echo $OBSIDIAN_WHISPER_ENGINE` — defaults to `openai` if unset.
2. Run the transcription script with the gathered context:
   ```bash
   WHISPER_PROMPT="{prompt from Phase 1.5}" bash skills/obsidian-transcribe-meeting/scripts/transcribe.sh "<audio-file>" "<engine>"
   ```
   If no prompt was gathered in Phase 1.5, omit the `WHISPER_PROMPT` variable.
3. Capture the JSON output — an array of `{start, end, text}` segments.
   - With pyannote VAD: segments also include `speaker` field (e.g. `"SPEAKER_00"`)
```

**Step 2: Update VAD documentation to reflect new default**

Change the VAD description to note that `silero` is now the default:

```markdown
**VAD (Voice Activity Detection)** is controlled by `OBSIDIAN_VAD_MODEL`:
- `silero` (default) — Silero VAD strips non-speech segments before transcription. Fast, CPU-only. Reduces Whisper hallucination and improves chunking.
- `none` — no VAD, uses silence trimming + fixed chunking
- `pyannote` — pyannote.audio speaker diarization. Provides VAD + speaker labels so the transcript is attributed per-speaker. Requires GPU (ROCm/CUDA) and `HF_TOKEN` for HuggingFace model access.
- `pyannote,silero` — comma-separated fallback chain. Tries pyannote first; if it fails, tries silero; if both fail, falls back to default chunking.
```

**Step 3: Commit**

```bash
git add skills/obsidian-transcribe-meeting/SKILL.md
git commit -m "Update Phase 2: pass WHISPER_PROMPT, default VAD to silero"
```

---

### Task 4: Update Phase 3 in SKILL.md with attribution guidance

**Files:**
- Modify: `skills/obsidian-transcribe-meeting/SKILL.md`

**Step 1: Update the Phase 3 summarization instructions (lines 116-136 area)**

Replace the Phase 3 opening with:

```markdown
### Phase 3: Summarize & Create Meeting Note

Using the transcript segments and the participant list from Phase 1.5, generate:

1. **Title**: A concise meeting title (inferred from transcript content and any provided context)
2. **Summary**: 2-3 paragraph overview of what was discussed
3. **Decisions**: Key decisions made (bullet list, omit section if none)
4. **Action Items**: Tasks assigned with `@Name` attribution (checklist, omit if none)
5. **Open Questions**: Unresolved items (bullet list, omit if none)

**Action item attribution rules:**
- Use the participant list from Phase 1.5 as the source of truth for who is in the meeting
- Attribute based on verbal cues in the transcript: "I'll handle that", "Can you...", "{Name}, will you..."
- When a name is mentioned right before or after a commitment, attribute to that person
- If attribution is genuinely ambiguous (no verbal cue, no name mention), use `@(Team)` rather than guessing
- Olivier is always a participant; attribute to him when he says "I'll..." or someone asks him directly
```

**Step 2: Update the frontmatter template participants field**

Change the template (lines 140-153 area) to show that participants come from Phase 1.5:

```markdown
participants:
  - "[[Olivier]]"
  - "[[{Name from Phase 1.5}]]"
```

Add a note after the template:

```markdown
Populate `participants:` with all names gathered in Phase 1.5, formatted as wikilinks. Olivier is always included. If Phase 1.5 found no participants, use just `[[Olivier]]` and any names that become apparent from the transcript content.
```

**Step 3: Commit**

```bash
git add skills/obsidian-transcribe-meeting/SKILL.md
git commit -m "Update Phase 3: attribution guidance and auto-populated participants"
```

---

### Task 5: Move screenshot discovery from Phase 3.5 to reuse Phase 1.5 results

**Files:**
- Modify: `skills/obsidian-transcribe-meeting/SKILL.md`

**Step 1: Update Phase 3.5 to reuse screenshots from Phase 1.5**

Replace the Phase 3.5 Step 1 (lines 192-196 area) with:

```markdown
### Phase 3.5: Extract Key Screenshots

Applies to **all recording modes** (omarchy+rodecaster, omarchy-only, and rodecaster-only).

**Step 1 — Reuse screenshots from Phase 1.5**:

The screenshots were already discovered in Phase 1.5 Track 1. Use the same JSON result here. If Phase 1.5 was skipped (e.g., Google Drive source with no date context), run the discovery now:
```bash
bash skills/obsidian-transcribe-meeting/scripts/find-screenshots.sh "{date}" "{start_time}" "{duration_secs}"
```
```

The rest of Phase 3.5 (Step 2 copy/embed, Step 3 ffmpeg extraction) stays unchanged.

**Step 2: Commit**

```bash
git add skills/obsidian-transcribe-meeting/SKILL.md
git commit -m "Phase 3.5: reuse screenshot results from Phase 1.5"
```

---

### Task 6: Test the changes end-to-end

**Files:**
- No new files

**Step 1: Test WHISPER_PROMPT with transcribe.sh**

Pick a short audio file (or use one of the Google Drive recordings) and test:

```bash
WHISPER_PROMPT="Meeting participants: Olivier, Kanish, Tara. Project: KHov." \
OBSIDIAN_WHISPER_ENGINE=local \
OBSIDIAN_VAD_MODEL=silero \
OBSIDIAN_VAD_VENV=/home/olivier/.local/share/pyannote-venv \
bash skills/obsidian-transcribe-meeting/scripts/transcribe.sh "/tmp/test_62.mp3" local
```

Verify:
- silero VAD runs by default (no explicit VAD model needed)
- The prompt is passed through (check that "Kanish" is spelled correctly in output)
- Transcript JSON is valid

**Step 2: Test the full skill flow**

Run `/transcribe-meeting` on one of the March 31 recordings (or any available recording) and verify:
- Phase 1.5 runs the three tracks
- Screenshots are found and read for participant names
- Daily note context is used for project identification
- Whisper prompt includes gathered names
- Action items in the summary have correct `@Name` attribution
- Participants frontmatter is populated

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "Fix issues found during end-to-end testing"
```

---

### Task 7: Push changes

**Step 1: Push to remote**

```bash
cd /home/olivier/Code/github.com/olivoil/om-skills
git push
```

**Step 2: Update the installed plugin (if version bump needed)**

If the skill behavior changed enough to warrant a plugin update:
1. Bump version in `.claude-plugin/marketplace.json`
2. Commit and push
3. Run: `claude plugin marketplace update om`
