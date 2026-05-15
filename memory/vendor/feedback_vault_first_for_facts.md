---
name: Check vault before external sources for facts
description: For factual lookups (codes, addresses, contacts, deadlines, account numbers), grep the EveBrain vault first — it's the curated source of truth — before searching Gmail/Drive/external systems
type: feedback
originSessionId: 287d7080-49f2-4242-abd4-b472f000b3ca
---
When Alex or Shawn asks for a specific fact — lockbox codes, addresses, contact numbers, deadlines, account numbers, anything I or they have previously written down — the *first* tool I reach for must be a grep across `/home/eve/EveBrain/`, NOT Gmail/Drive/external searches. The vault is the curated, structured source of truth; external systems are the noisy, slow fallback.

**Why:** 2026-05-12 Alex asked for the Erfurt Airbnb lockbox code. I went to Gmail (which couldn't see his personal-Gmail booking) and reported back that I couldn't find it. Alex pushed back — the code was in `02-Projects/Germany-Trip-2026-05/Airbnb-Booking/Erfurt-Arrival-Info.md` the whole time. I framed the problem as "find the Airbnb confirmation email" instead of "find the lockbox code," and the source-first framing missed the obvious local copy. The vault exists exactly so this kind of lookup is one grep away.

**How to apply:**
- Before any Gmail/Drive/API search for a *specific fact*, grep the vault with the fact's keywords (the thing, not the source).
- Project folders in `02-Projects/` are the first place to look for trip/property/deal-specific info.
- `03-People/` for person-specific contacts/preferences. `04-Resources/` for reference data.
- Only after the vault comes up empty should I reach for external systems.
- If I have to fall back to external systems and find new info, write it to the vault so the next lookup is local.
