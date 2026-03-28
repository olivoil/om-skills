#!/usr/bin/env python3
"""Voice Activity Detection and optional speaker diarization.

Usage: python3 vad.py <audio-file>

Outputs JSON speech segments to stdout:
  Silero:   [{"start": 0.0, "end": 5.2}, ...]
  Pyannote: [{"start": 0.0, "end": 5.2, "speaker": "SPEAKER_00"}, ...]

Environment:
  OBSIDIAN_VAD_MODEL — "silero", "pyannote", or "none" (default: "none")
  HF_TOKEN             — HuggingFace token (required for pyannote)

Requires:
  silero:   pip install torch torchaudio
  pyannote: pip install torch pyannote.audio
"""

import json
import os
import sys

def run_silero(audio_file: str) -> list[dict]:
    """Run Silero VAD and return speech segments."""
    import torch
    torch.set_num_threads(4)

    model, utils = torch.hub.load(
        repo_or_dir="snakers4/silero-vad",
        model="silero_vad",
        trust_repo=True,
    )
    (get_speech_timestamps, _, read_audio, _, _) = utils

    wav = read_audio(audio_file, sampling_rate=16000)
    speech_timestamps = get_speech_timestamps(
        wav,
        model,
        sampling_rate=16000,
        min_speech_duration_ms=500,
        min_silence_duration_ms=300,
        speech_pad_ms=200,
        return_seconds=True,
    )

    return [{"start": round(s["start"], 3), "end": round(s["end"], 3)} for s in speech_timestamps]


def run_pyannote(audio_file: str) -> list[dict]:
    """Run pyannote speaker diarization (includes VAD)."""
    import torch
    from pyannote.audio import Pipeline

    hf_token = os.environ.get("HF_TOKEN")
    if not hf_token:
        print("Error: HF_TOKEN required for pyannote (accept model terms at huggingface.co/pyannote/speaker-diarization-3.1)", file=sys.stderr)
        sys.exit(1)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"pyannote: using device {device}", file=sys.stderr)

    pipeline = Pipeline.from_pretrained(
        "pyannote/speaker-diarization-3.1",
        use_auth_token=hf_token,
    )
    pipeline.to(device)

    diarization = pipeline(audio_file)

    segments = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        segments.append({
            "start": round(turn.start, 3),
            "end": round(turn.end, 3),
            "speaker": speaker,
        })

    return segments


def merge_segments(segments: list[dict], max_gap: float = 2.0, max_duration: float = 30.0) -> list[dict]:
    """Merge adjacent segments with small gaps into larger chunks.

    Groups by speaker if speaker labels are present. Caps merged segments at
    max_duration seconds to keep Whisper chunks manageable.
    """
    if not segments:
        return []

    has_speakers = "speaker" in segments[0]
    merged = []
    current = dict(segments[0])

    for seg in segments[1:]:
        same_speaker = (not has_speakers) or (seg["speaker"] == current.get("speaker"))
        gap = seg["start"] - current["end"]
        would_be_duration = seg["end"] - current["start"]

        if same_speaker and gap <= max_gap and would_be_duration <= max_duration:
            current["end"] = seg["end"]
        else:
            merged.append(current)
            current = dict(seg)

    merged.append(current)
    return merged


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <audio-file>", file=sys.stderr)
        sys.exit(1)

    audio_file = sys.argv[1]
    model = os.environ.get("OBSIDIAN_VAD_MODEL", "none").lower()

    if model == "none":
        # No VAD — output empty array so caller knows to use default behavior
        print("[]")
        return

    if not os.path.isfile(audio_file):
        print(f"Error: File not found: {audio_file}", file=sys.stderr)
        sys.exit(1)

    print(f"Running VAD model: {model}", file=sys.stderr)

    if model == "silero":
        raw_segments = run_silero(audio_file)
    elif model == "pyannote":
        raw_segments = run_pyannote(audio_file)
    else:
        print(f"Error: Unknown VAD model '{model}'. Use 'none', 'silero', or 'pyannote'.", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(raw_segments)} speech segments", file=sys.stderr)

    merged = merge_segments(raw_segments)
    print(f"Merged into {len(merged)} chunks", file=sys.stderr)

    json.dump(merged, sys.stdout, indent=2)
    print()  # trailing newline


if __name__ == "__main__":
    main()
