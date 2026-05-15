---
name: WhatsApp blue check IS the receipt — no 🧠 emoji on WhatsApp
description: For WhatsApp messages from Alex/Shawn, never send 🧠 receipt — the bridge fires MarkRead (blue ✓✓) only after Eve actually wakes
type: feedback
originSessionId: 3867eec9-68c4-4f50-b5f3-2ada3e72d2e7
---
**Rule:** On WhatsApp, **do not** send the 🧠 emoji as a receipt. The blue ✓✓ checkmark serves that role now.

**Why:** Alex flagged 2026-05-05 that the brain emoji was redundant clutter once we wired up read receipts. He also wanted the blue check to be *meaningful* — i.e., it should only appear if Eve is genuinely alive to handle the message, not just because the bridge process accepted it.

**Architecture (locked 2026-05-05):**
- Bridge (`/home/eve/whatsapp-mcp/whatsapp-bridge/`) calls `client.MarkRead(...)` **inside `MaybeWakeOnMessage`** (in `wake.go`), only after the wake-hook HTTP POST to `127.0.0.1:3000/wake` returns 2xx.
- That means: wake hook succeeded → SharedBrain accepted the prompt → Eve is processing → MarkRead fires → blue ✓✓ shows.
- If SharedBrain is down or Claude can't be reached, no MarkRead, no blue check — exactly the signal Alex wants.
- Wake-prompt template in `wake.go` was updated to explicitly tell Eve **"do NOT send a 🧠 receipt — the blue check is the receipt"** so the directive survives across sessions.

**How to apply:**
- WhatsApp DMs and groups with Alex/Shawn: never send 🧠. Skip straight to the actual reply.
- Google Chat: 🧠 receipt rule still applies (per `feedback_read_eve_personality_first.md`) — those channels don't have a blue-check equivalent.
- If a wake-prompt template still says "send 🧠", that's a stale template — the source of truth is `wake.go` lines ~184-193. The current text already excludes the 🧠 instruction.
