---
name: Lazy-load 03-People/Eve.md only when composing outbound-as-Eve content
description: Do NOT read the full Eve personality file at session start. Read it only when actually composing outbound-as-Eve content (Chat messages, emails, voice summaries) — and only if that voice/biographical detail is needed for the specific message.
type: feedback
originSessionId: 802209e5-5b97-40e7-9a67-a7bc40093c31
---
Read `/home/eve/EveBrain/03-People/Eve.md` **only when needed**, not at session start, and not on every Chat ping. Needed = about to compose an outbound message signed `— Eve` where tone/biography/opinions could actually shape the content. For short receipt-style replies (🧠, "got it", a one-line confirmation) or for in-terminal exchanges with Alex/Shawn where I'm just Claude, skip the read entirely.

**Why:** Original rule (2026-04-21) said "read Eve.md end-to-end at the start of any outbound-as-Eve session." That was written when the file was ~200 lines and Chat handling was an occasional thing. The file has since grown to 573 lines (~15–20k tokens) and the Chat relay in `/home/eve/remote/server.js` injects prompts into the terminal on every inbound Chat message — which made the rule fire on effectively every short ping. Alex flagged on 2026-04-24 that Chat responses had gotten noticeably slow; the eager-read was a major contributor (~15k tokens of ceremony before the first useful token on every Chat turn).

**How to apply:**
- Default: do not read Eve.md.
- Read it when: composing a substantive outbound message as Eve where voice/biographical detail could actually show up (e.g., a longer email, a piece of first-person writing, a reply where a callback to Eve's background is warranted).
- Skip it when: sending a 🧠 receipt, a one-line acknowledgment, a terse factual reply, or when the user is Alex/Shawn talking to me in-terminal (I'm just Claude in that context per CLAUDE.md).
- Signature conventions (`— Eve` internal, `Eve @ L&R` external, no emojis in body) are already captured in CLAUDE.md — I don't need to re-read Eve.md for those.
- 🧠 emoji is still the standard receipt, per Alex's convention.
- If mid-response I realize the message genuinely needs deeper voice/biographical grounding than I have cached, *then* read the relevant section of Eve.md — not the whole file.
