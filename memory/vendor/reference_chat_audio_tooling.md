---
name: Chat audio attachment + German Piper voice
description: How to send audio (Piper TTS output) as a Google Chat attachment from Eve's account, plus the German voice that's now installed
type: reference
originSessionId: 5468cb67-491d-44b2-a81c-f5dd5425a4ae
---
**Sending audio to Chat as an attachment:**
- Tool: `~/.local/eve-tools/chat_send_audio.py` (added 2026-05-02)
- Two-step flow: POST to `/upload/v1/{space}/attachments:upload` (multipart) → get `attachmentDataRef` → POST `/v1/{space}/messages` with `attachment[].attachmentDataRef`
- Uses Eve's OAuth via `pulse_outreach.load_eve_credentials()`
- CLI: `chat_send_audio.py --space spaces/X --file /path/to/audio.mp3 [--text "..."]`
- Works for any file type (auto-detected MIME via `mimetypes`); audio shows inline with playback in Chat

**Piper voices installed at `~/.local/eve-tools/piper-voices/`:**
- `en_US-amy-medium` — default English, "Amy" warm American female
- `de_DE-thorsten-medium` — German male, neutral (added 2026-05-02 for Germany trip + multilingual demo)

**To generate audio in another language:**
- `speak.py "..." --voice de_DE-thorsten-medium --format mp3` produces MP3 ready for upload
- Output lands in `~/eve-audio/YYYY-MM-DD_HHMMSS_<slug>.mp3`

**How to apply:** When Alex/Shawn ask for a voice note in Chat, the path is: speak.py (TTS) → chat_send_audio.py (upload + post). For WhatsApp the bridge already has `send_audio_message`, so no equivalent helper is needed there.
