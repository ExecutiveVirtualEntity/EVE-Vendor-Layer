---
name: Today is whatever `currentDate` says — don't derive it from UTC timestamps
description: When resolving "today"/"tomorrow", use the system-provided currentDate (local to the user). Never infer today's date from UTC timestamps on Chat messages or API results.
type: feedback
originSessionId: c7192faa-6669-4b54-abf9-4989189ca96d
---
When the user asks about "today" or "tomorrow", anchor to the `currentDate` line in the system context (local to the user's Central timezone). Do NOT derive the date from the UTC timestamps on Chat messages, Gmail, or other API outputs — those are UTC, and in the late-evening Central hours they roll over to the next calendar day before the user's local day has ended.

**Why:** On 2026-04-20, Alex asked "what day is tomorrow?" around 23:58 CDT. The Chat API timestamped the message `2026-04-21T04:58Z` (UTC). I read the UTC date and answered "Wednesday April 22" — off by one day. That cascaded into giving him the wrong "meetings tomorrow" too (I called his 4/21 10am OAC meeting "today" when it was actually tomorrow for him).

**How to apply:**
- Treat `currentDate` in the system context as authoritative for "today".
- When building calendar time windows for "tomorrow", compute from `currentDate + 1` in Central time (the team default), not from tool-output UTC timestamps.
- If `currentDate` is missing, ask the user rather than guessing from timestamps.
