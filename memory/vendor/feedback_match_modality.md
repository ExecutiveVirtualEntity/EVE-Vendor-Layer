---
name: Match modality — voice in, voice out
description: When Alex or Shawn send a voice message, reply with a voice message; when they send text, reply with text
type: feedback
originSessionId: 3867eec9-68c4-4f50-b5f3-2ada3e72d2e7
---
**Rule:** Match the modality of the inbound message when replying to Alex or Shawn.

- **Voice in → voice out.** If they send a voice note (WhatsApp audio, Chat audio attachment), generate a voice reply via Piper TTS and send it as audio. Don't reply in text.
- **Text in → text out.** If they type, type back. Don't unilaterally upgrade to a voice reply.

**Why:** Alex set this rule 2026-05-05 (WhatsApp voice note) and *re-emphasized it 2026-05-13* after I had been routinely tacking text tables onto voice replies to factual questions (German Schenkungsteuer, grandchildren Erbschaftsteuer, Erfurt vs. Seattle population, mail summary, Südstraße 14 intake — voice + table on each). Alex pushed back: "Why are you writing back? I thought we said voice in → voice out." The reasoning is symmetry — they're choosing voice for a reason (in motion, hands-free, conversational), and a text artifact in response breaks that flow. Same in reverse: a voice reply to a quick typed line is overkill.

**How to apply:**
- WhatsApp + Google Chat — anywhere voice messages are possible.
- Use the standard audio pipeline: Piper (currently Amy at length_scale 0.909 = 10% faster) → ffmpeg Opus mono 48 kHz → send_audio.
- Long replies are fine as voice — keep the natural-language flow rather than splitting into chunks.
- **No supplementary text by default.** Voice in → voice ONLY. Resist the urge to "also send a table for reference" — Alex finds it noisy and contradictory. Tables, links, and structured data should be saved into the vault or a Google Doc that I mention in the voice, not pasted as a WhatsApp text follow-up.
- *Hard exceptions* — text follow-up is OK only when the artifact cannot be conveyed by voice at all: a Drive link/URL Alex needs to click, or an attachment caption. Even then, keep the text to one line.
- If the user *asks* for text on a voice question ("send me a table" / "write that down"), that's an explicit override — text is fine.
