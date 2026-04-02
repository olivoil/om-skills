# Transcription Context Gathering & Improved Attribution

**Date:** 2026-04-02
**Skill:** obsidian-transcribe-meeting

## Problem

Meeting transcriptions produce good text but frequently mis-attribute action items to the wrong person. Whisper also misspells participant names and project-specific terms because it has no context about who's in the meeting.

## Solution

Add a pre-transcription context gathering phase that discovers participant names and project vocabulary before whisper runs. Use this context to:
1. Seed whisper's `initial_prompt` for better name/term spelling
2. Provide Claude with an explicit participant list for action item attribution
3. Auto-populate the `participants:` frontmatter field

## Design

### Phase 1.5: Gather Context (new phase)

Runs after recording discovery (Phase 1), before transcription (Phase 2). Three parallel tracks:

**Track 1: Screenshots**
- Reuse `find-screenshots.sh` with the recording start time and full meeting duration
- Claude reads the screenshot(s) with vision, extracts participant names from the Teams/Zoom/Meet UI
- Output: list of names as they appear on screen
- Same screenshot results are reused later in Phase 3.5 for embedding

**Track 2: Vault context**
- Read the daily note for the target date
- Find which project the recording maps to (from time entry lines or user-provided context)
- Read the project page for known team members (from `## Team`, `## Participants`, or wikilinks to people pages)
- Output: project name, known team member names, project-specific terminology

**Track 3: Quick first-pass**
- Extract first 90 seconds of audio with ffmpeg
- Run whisper on just that clip (no prompt, fast since it's tiny)
- Scan the text for proper nouns / name-like words
- Output: names mentioned early in the recording

**Combine:** Merge and deduplicate names from all three tracks. Build a whisper prompt string like:
```
Meeting participants: Olivier, Kanish, Tara, Dinesh, Adam. Project: KHov. Topics: deployment pipelines, QA issues, Optimizely CMS.
```

### Phase 2: Transcribe (changes)

- New `WHISPER_PROMPT` env var in `transcribe.sh`
  - OpenAI API: `-F "prompt=$WHISPER_PROMPT"`
  - whisper-cli: `--prompt "$WHISPER_PROMPT"`
- Default `OBSIDIAN_VAD_MODEL` changed from `none` to `silero`

### Phase 3: Summarize (changes)

- Participant list passed to Claude for summary generation
- Attribution guidance: use verbal cues ("I'll handle that", "Can you..."), name mentions near commitments
- When attribution is ambiguous, use `@(Team)` rather than guessing wrong
- Participant names populate `participants:` frontmatter automatically
- Screenshot discovery moved to Phase 1.5 (results reused in Phase 3.5 for embedding)

## Script Changes

### Modified: `transcribe.sh`
- Accept `WHISPER_PROMPT` env var
- Pass to OpenAI API and whisper-cli
- Change default `OBSIDIAN_VAD_MODEL` from `none` to `silero`

### Modified: `SKILL.md`
- Insert Phase 1.5 between Phase 1 and Phase 2
- Update Phase 2 to set `WHISPER_PROMPT` from gathered context
- Update Phase 3 with attribution guidance and participant population
- Move screenshot discovery from Phase 3.5 to Phase 1.5 (reuse results for both)

## User Behavior Changes

- Take screenshots during meetings that show the participant panel (Teams/Zoom/Meet)
- Optionally mention participant names at the start of recordings
- Both are natural actions that feed into the automated context gathering
