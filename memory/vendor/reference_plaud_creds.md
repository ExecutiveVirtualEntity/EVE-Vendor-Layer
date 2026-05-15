---
name: Plaud credentials + auto-refresh
description: ~/.config/eve/plaud.env holds UT/WT/WRT for web.plaud.ai; WT auto-refreshes via UT (no more manual re-extraction)
type: reference
originSessionId: 3867eec9-68c4-4f50-b5f3-2ada3e72d2e7
---

Plaud cloud auth lives at `~/.config/eve/plaud.env` (0600 perms, owner: eve).

**Token model:**

| Token | Lifetime | Used for |
|---|---|---|
| **UT** (User Token, `typ:"UT"`) | ~10 months | `/user/me`, `/user-app/profile/account/me`, **and** minting WTs via `/user-app/auth/workspace/token/<ws_id>` |
| **WT** (Workspace Token, `typ:"WT"`) | 24 hours | `/file/*`, `/filetag/`, all workspace-scoped reads |
| **WRT** (Workspace Refresh, `typ:"WRT"`) | 30 days | Emitted alongside each WT but **not used for refresh** — UT mints WTs directly |

**Auto-refresh wired up 2026-05-06.** `PlaudClient.ensure_fresh_wt()` runs at the start of every `plaud_ingest.py` invocation; refreshes when WT has < 1h remaining and rewrites `~/.config/eve/plaud.env` in place (preserves comments + non-token lines). The cron now self-heals — only manual rotation needed is the **UT every ~10 months**.

**Refresh endpoint** (validated 2026-05-06 from Plaud web bundle):
- `POST https://api.plaud.ai/user-app/auth/workspace/token/<workspace_id>`
- `Authorization: <UT>` (the `bearer eyJ...` value as-is)
- Body: `{}` (literal empty JSON object)
- Response data keys: `workspace_token`, `refresh_token`, `expires_in`, `wt_expires_at`, `refresh_expires_in`, `refresh_expires_at`, `workspace_id`, `member_id`, `role`

**Gotcha:** Plaud's WAF rejects the default Python-urllib UA with HTTP 403. `plaud_client.py` sets `User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0` on every request.

**Auth header form:** UT value already starts with `bearer ` (lowercase b), WT value starts with `Bearer ` (uppercase). Both work as-is when assigned directly to the `Authorization` header.

**To rotate the UT** (next around Q1 2027):
1. In Firefox at https://web.plaud.ai (logged in), open DevTools → Storage → Local Storage → `https://web.plaud.ai`
2. The UT is the entry `pid_tokenstr` (or `pld_tokenstr` on older Plaud builds) — value starts with `bearer eyJ...`
3. Replace `PLAUD_UT="..."` in `~/.config/eve/plaud.env`. Auto-refresh handles WT/WRT from there.
