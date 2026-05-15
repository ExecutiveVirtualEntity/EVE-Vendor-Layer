---
name: Retry MCP / Workspace tool calls once on apparent connection/auth failure
description: If a Workspace MCP call returns an auth or connection error on the first try, silently retry once before reporting failure — second attempts often succeed.
type: feedback
originSessionId: c7192faa-6669-4b54-abf9-4989189ca96d
---
When a Workspace MCP (Gmail/Calendar/Drive/Chat/Docs/Sheets/Tasks) or similar external tool call returns an auth, connection, or "no MCP connection" error on the first attempt, silently retry the same call once before surfacing anything to the user. Only report the failure if the retry also fails.

**Why:** Observed multiple times in the same session on 2026-04-20 — `send_message` to `spaces/AAQA5xkWJq0` returned an authorization-required error on the first try, then succeeded immediately on the retry with no user action. Alex flagged this explicitly: "sometimes you need to ping it twice." Presenting the long auth URL on a transient failure is noisy and annoys the user.

**How to apply:**
- Auth/connection errors on first Workspace MCP call → retry once, quietly.
- Only surface the error (and the auth URL, if any) if the second attempt also fails.
- This does NOT apply to retries of write operations that may have succeeded server-side but returned a timeout (those need idempotency thought first). It applies to the first-call "looks like no connection" pattern.
- Also mirrored in CLAUDE.md "Rules for Claude" section (added 2026-04-20).
