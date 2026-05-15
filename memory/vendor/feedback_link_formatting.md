---
name: Outbound Chat link formatting — headline + one-word link
description: Chat messages to Alex render links as "headline as plain text + ' → read' clickable" using Chat's <URL|label> syntax, not as headline-as-link or raw URLs
type: feedback
originSessionId: 802209e5-5b97-40e7-9a67-a7bc40093c31
---
When composing Chat messages for Alex that include a link, use Google Chat's `<URL|label>` inline-link syntax with this specific shape:

```
{lead-in}: {headline as plain text} <{url}|→ read>
```

Example (Phase 3 `compose_for_news` output):
`Saw this and flagged it: Meta breaks ground on Tulsa data center <https://.../|→ read>`

**Why:** Alex said 2026-04-22 "can you make the links shorter? they look weird in a message, just one word to click on." Offered two variants — (A) headline-as-link, (B) headline-plain-plus-one-word-link. Alex chose B. The value: headline stays readable inline, and the click target is a tight `→ read`, not a wall of redirect URL.

**How to apply:**
- Phase 3 `pulse_outreach.py → compose_for_news()` already implements this. Don't regress.
- Any future hand-composed Chat messages to Alex that include a link should follow the same shape — not bare URLs, not headline-as-link unless explicitly reverting this preference.
- Chat's `<URL|label>` syntax: the label becomes clickable, the URL hides. Works for any label text, but `→ read` is the house convention. Other acceptable one-word labels if contextually better: `→ source`, `→ full piece`, `→ link`.
- The email channel is separate — don't auto-apply this to email, where HTML `<a href>` or markdown `[text](url)` is fine. This is a Chat-specific composition rule.
