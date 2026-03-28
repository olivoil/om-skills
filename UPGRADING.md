# Upgrading

## 4.0.0

### Breaking Changes: Environment Variable Renames

All custom environment variables now use a consistent `OBSIDIAN_` prefix. Update your shell profile, `.env` files, or Claude Code settings:

| Old | New |
|---|---|
| `RODECASTER_MOUNT` | `OBSIDIAN_RODECASTER_MOUNT` |
| `OMARCHY_SCREENSHOT_DIR` | `OBSIDIAN_SCREENSHOT_DIR` |

These variables were renamed for consistency with `OBSIDIAN_WHISPER_ENGINE`. If unset, the scripts continue to auto-detect as before.

### New Feature: Voice Activity Detection (VAD)

A new `OBSIDIAN_VAD_MODEL` environment variable controls optional VAD preprocessing for the transcription skill. Three modes are available:

- `none` (default) — no VAD, existing behavior unchanged
- `silero` — fast CPU-based VAD for better chunking and reduced Whisper hallucination
- `pyannote` — speaker diarization with VAD, outputs speaker-attributed transcripts

#### Installing Silero VAD

```bash
pip install torch torchaudio
```

No GPU required. Runs in milliseconds on CPU.

#### Installing pyannote.audio

```bash
# For ROCm (AMD GPUs like 7900 XTX):
pip install torch --index-url https://download.pytorch.org/whl/rocm6.x
pip install pyannote.audio

# For CUDA (NVIDIA GPUs):
pip install torch pyannote.audio

# CPU-only (slower, but works):
pip install torch pyannote.audio
```

Then:

1. Accept the model terms at https://huggingface.co/pyannote/speaker-diarization-3.1
2. Set `HF_TOKEN` to your HuggingFace access token

#### Usage

Set the env var before running the transcription skill:

```bash
export OBSIDIAN_VAD_MODEL=silero   # or pyannote, or none
```

If VAD fails (missing dependencies, etc.), the skill falls back gracefully to the default chunking behavior.
