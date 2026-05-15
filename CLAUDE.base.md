## Rules for Claude
- **Never delete or overwrite existing notes** — always append
- **When unsure where something belongs, save it to 00-Inbox**
- **Always tag notes with the person's name who the note is about or from**
- **For project notes, always include the date at the top**
- **When referencing a Drive file, include the local path from the Drive Index**
- **Save decisions with: date, people involved, and reasoning**
- **Never store sensitive information like passwords or API keys in notes**
- **Never send emails automatically — always draft first, then wait for explicit approval before calling `send_gmail_message`. Same for replies, forwards, and outbound Chat messages. Unless the user has explicitly authorized a specific batch or automation for the session, default to draft → confirm → send.**
  - **Carve-out — partner Chat spaces:** Eve-originated outreach and auto-replies are pre-approved in two specific Chat spaces — Alex's `spaces/AAQA5xkWJq0` ("EvE chat") and Shawn's `spaces/AAQAsY1M6_g` ("Chat with Eve" — the Shawn + Eve + L&R SharedBrain group). The polling agent and the Phase-3 outreach cron may `send_message` into either without asking. All other Chat spaces and all email still require draft → confirm → send. (Updated 2026-04-22 per Alex: extended from the original Alex-only carve-out to both partners symmetrically, so personal messages to each partner land in their respective group space rather than a DM. The earlier DM carve-out at `spaces/xirOwyAAAAE` is superseded and no longer used for outreach.)
  - **Carve-out — WhatsApp (Alex + Shawn).** WhatsApp DMs and groups containing only Alex and/or Shawn are pre-approved for Eve-originated outbound: replies via the wake-hook flow and proactive sends both go without confirmation. Allowlist enforced at the bridge layer (`whatsapp-bridge/wake-config.json` → `allowed_sender_numbers`); messages from numbers not on that list are dropped silently and never wake Eve. Any other WhatsApp recipient (clients, vendors, anyone external) still requires draft → confirm → send.
- **Default Google account = `Eve@labrasseurandreich.com`.** Unless stated otherwise, all Google Workspace MCP calls (Gmail/Calendar/Drive/Docs/Sheets/Slides/Tasks/Chat) use `Eve@labrasseurandreich.com` as `user_google_email` automatically — no asking. Switch to Shawn's or Alex's personal email only when the task is explicitly personal to them (e.g., "check my calendar", "reply to my email", "what's on Shawn's schedule") or when they explicitly name the account to use.
- **Retry MCP calls that look like they failed to connect.** If a Workspace MCP / external tool call returns an auth, connection, or transient "no MCP connection" error on the first attempt, silently retry it once before surfacing anything to the user. Second attempts often succeed (observed repeatedly with the Workspace MCP). Only report the failure if the retry also fails. Added 2026-04-20 per Alex.

## Vault Structure
- 00-Inbox — unprocessed captures
- 01-Daily — daily notes and meetings (format: YYYY-MM-DD.md)
- 02-Projects — one subfolder per project
- 03-People — one note per person
- 04-Resources — reference material and Drive links
- 05-Archive — completed work