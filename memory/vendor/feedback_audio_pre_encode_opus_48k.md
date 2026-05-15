---
name: Always pre-encode audio to Opus 48 kHz
description: All Eve-generated audio (WhatsApp + Chat) must be pre-encoded as Opus mono 48 kHz before sending — never let the bridge re-encode raw Piper WAV
type: feedback
originSessionId: 3867eec9-68c4-4f50-b5f3-2ada3e72d2e7
---
When generating voice messages with Piper TTS for WhatsApp or Google Chat, **always** pre-encode the WAV to Opus mono 48 kHz before handing the file to the send tool. Do not send the raw 22 kHz WAV that Piper outputs.

**Locked pipeline (Alex confirmed sounds clean — refined 2026-05-06):**
```
piper -m <voice>.onnx --length-scale 1.0 --sentence-silence 0.30 --output-file out.wav <<< "text"
# atempo=1.2 = 20% faster, pitch-preserved post-process
ffmpeg -y -i out.wav -filter:a "atempo=1.2" -ar 48000 -ac 1 -c:a libopus -b:a 32k -application voip out.ogg
# then send out.ogg via mcp__whatsapp__send_audio_message or chat attachment
```

**Why:** WhatsApp bridge auto-converts unknown audio and introduces noise. Pre-encoding to Opus 48 kHz fixes that. ffmpeg atempo time-stretches the rendered audio (pitch preserved, no model artifacts) — fundamentally different from Piper's length-scale, which regenerates phonemes at a different rate and introduces clipping + distortion.

**Speed approach (validated 2026-05-06):**
- Synthesis stays at length-scale=1.0 always.
- For faster delivery, post-process with `ffmpeg -filter:a "atempo=1.2"` — Alex confirmed "that's perfect" 2026-05-06 14:04 PT (mid-flight to FRA).
- atempo range 0.5–2.0 in a single pass; chain filters for more (`atempo=2.0,atempo=1.5` = 3x). Stay close to 1.2 for normal speech — too much faster gets staccato.

**Avoid (failed previously):**
- Piper `--length-scale` < 1.0 — Piper outputs ~9 dB louder WAVs at 0.909, push peaks into clipping AND introduce phoneme distortion at the model level. Loudnorm doesn't fix it. Alex A/B-tested 2026-05-05: length=1.0 = clean, length=0.909 = "destroyed" (multiple voices).
- Loudnorm or volume filters — don't fix distortion, just make things quieter.

**How to apply:**
- Default audio send: Piper at length=1.0 + ffmpeg atempo=1.2 + Opus 48k mono. Use this every time unless asked otherwise.
- Default voice: Amy (en_US-amy-medium). Other female voices at `/home/eve/.local/eve-tools/piper-voices/`: Kristin, Kathleen, hfc_female, Jenny (en_GB). German: thorsten-medium.
