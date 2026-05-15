---
name: Share Drive uploads with the relevant partner(s) by default
description: When Eve uploads to her own Drive and the file is meant for Alex or Shawn, grant them reader access in the same step — don't make them ask
type: feedback
originSessionId: 802209e5-5b97-40e7-9a67-a7bc40093c31
---
When Eve creates or uploads a file to her own Drive (`Eve@labrasseurandreich.com`) that is *meant for* Alex, Shawn, or both, grant them reader access immediately — as part of the same operation, not after they report "I don't have access."

**Why:** 2026-04-22, Eve voiced a website section as an MP3, uploaded to `Eve@...`'s Drive, and shared only the link. Alex got "no access" because he wasn't a permissioned viewer. The share step is small, but omitting it wastes a round-trip and makes the deliverable feel half-done.

**How to apply:**
- If the file's purpose is "I'm sending this to Alex" — grant Alex reader in the same call as the upload (via `manage_drive_access` action=grant, role=reader, send_notification=false).
- If it's "for Shawn" — same for Shawn.
- If it's "for the team" — grant both.
- If it's Eve-internal (logs, cached audio, scratch) — no share needed.
- `send_notification=false` avoids spamming them with a "Eve shared a file" email when the link is already in Chat.
- Doesn't apply to files that already live in shared Drive folders (e.g., shared team folders) — those inherit the folder's permissions.

When in doubt, share. Over-sharing with partners is cheap; making them ask is expensive.
