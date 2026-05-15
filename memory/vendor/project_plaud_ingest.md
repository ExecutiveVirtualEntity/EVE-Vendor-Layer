---
name: Plaud → vault ingest pipeline live
description: As of 2026-05-05, Eve pulls Plaud voice recordings hourly, transcribes with local Whisper, analyzes with Ollama, writes vault notes. Spec at 02-Projects/Plaud-Ingest/Spec.md.
type: project
originSessionId: 3867eec9-68c4-4f50-b5f3-2ada3e72d2e7
---
Plaud → vault ingest pipeline went live 2026-05-05 (early hours). Architecture: `~/.local/eve-tools/plaud_client.py` + `plaud_ingest.py`, hourly cron at `:30 6-22 * * *`, transcripts land in `00-Inbox/Plaud/YYYY-MM-DD-HHMM-<id>.md`. Audio cached at `~/.local/eve-tools/plaud-cache/`, never enters the vault. State (which file_ids are processed) at `~/.local/eve-tools/plaud-state/processed.json`.

**Why:** Alex bought a Plaud NotePin (serial `8810B50279360393`). He explicitly wanted Eve to do the transcription + analysis, NOT Plaud's intelligence layer — so client conversations never leave Eve's box, and summaries can use vault context.

**How to apply:**
- When Alex/Shawn mentions a recording or voice memo, check `00-Inbox/Plaud/` first — it likely already has the transcript.
- The current bottleneck: workspace token (WT) lifetime is ~24h. Refresh endpoint not yet identified — when WT expires, Alex needs to re-run the browser console one-liner: `console.log(JSON.stringify(Object.fromEntries(Object.entries(localStorage).filter(([k])=>k.startsWith('pld')))))` on web.plaud.ai (Firefox: needs Ctrl+Enter in multi-line editor mode), and re-write `~/.config/eve/plaud.env`.
- Whisper consistently mishears "Plaud"→"plow" and "Eve"→"eave" — known issue, not a regression. Initial_prompt fix is queued as v2.
- The current crontab uses Whisper `small` for speed; large-v3 is the manual override (`--force --model large-v3`) for important transcripts.
