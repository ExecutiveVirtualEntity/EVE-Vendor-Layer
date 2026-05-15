---
name: Re-encode video to H.264/AAC before sending via WhatsApp
description: WhatsApp's player can't decode mpeg4-codec MP4s (just black playback) — always re-encode to H.264/AAC first
type: feedback
originSessionId: 3867eec9-68c4-4f50-b5f3-2ada3e72d2e7
---
**Rule:** Any MP4 produced by an external tool must be re-encoded to **H.264 video + AAC audio + yuv420p, even pixel dimensions** before being sent via `mcp__whatsapp__send_file`. Bridge does no transcoding for video.

**Why:** SadTalker (and many other generators) emit `mpeg4` codec MP4s. WhatsApp's in-app player decodes only the **black background** of those files — Alex got audio-only playback 2026-05-05 from the first SadTalker demo. Re-encoded copy played correctly.

**Standard re-encode (works for SadTalker, OpenCV outputs, generic ffmpeg pipes):**
```
ffmpeg -y -i SOURCE.mp4 \
  -c:v libx264 -preset fast -crf 22 -pix_fmt yuv420p \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -c:a aac -b:a 96k \
  OUTPUT.mp4
```

The `scale=trunc(iw/2)*2:trunc(ih/2)*2` filter forces even dimensions (libx264 requires it for yuv420p). The `pix_fmt yuv420p` ensures broadest device compatibility.

**How to apply:**
- Whenever generating or relaying a video to WhatsApp.
- Quick check: `ffprobe -v error -show_entries stream=codec_name FILE.mp4` — if `codec_name=h264` you're fine; if `mpeg4`, re-encode.
- The same caveat applies to mov / m4v / weird containers — convert to a standard `.mp4`.
- Audio side: stick with AAC at 96-128 kbps. Opus-in-MP4 is technically valid but doesn't play on iOS WhatsApp.
