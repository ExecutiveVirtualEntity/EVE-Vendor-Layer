---
name: Gmail "granular consent" defaults to unchecked on personal-Gmail OAuth
description: When adding a personal Gmail to Workspace MCP, the consent screen checkboxes default OFF — if skipped, creds carry only userinfo.email/profile/openid and all Gmail/Drive/Calendar calls fail with re-auth prompts
type: feedback
originSessionId: 94c97d64-a283-4b32-a783-8e34e19ee183
---
When running the OAuth flow for a **personal Gmail address** (not a Workspace account) through the Workspace MCP, Google shows an unverified-app warning → *Advanced → Continue* → then a **"Select what <account> can access"** page with a checkbox list of granular permissions. **All checkboxes default to unchecked.** If the user clicks *Continue* without ticking them, the callback still succeeds and a credentials JSON still drops, but it only contains the basic identity scopes: `userinfo.email`, `userinfo.profile`, `openid`. Every subsequent Gmail/Drive/Calendar/Chat MCP call then fails with a fresh "Google Authentication Needed" error, which looks like the tokens didn't save but is actually a silent scope-stripping problem.

**Why:** Google's granular-consent UI for unverified apps (first seen 2026-04-23 during `info.buildfortomorrow@gmail.com` auth). Workspace-managed domains don't hit this screen — they inherit admin-approved scopes. Personal Gmails always will.

**How to apply:** When sending a new authorize link to Alex/Shawn for a personal Gmail account (`@gmail.com`), in the *same* Chat/email message flag the "**Select all**" / check-every-box step explicitly. If an auth completes but every subsequent call fails with the auth-needed error, first thing to check is `cat ~/.google_workspace_mcp/credentials/<email>.json | jq .scopes` — if only the three identity scopes are present, it's this bug, re-run `start_google_auth` and coach the checkbox step again. Don't assume a stuck port, a stale process, or a token-file corruption until scopes are ruled out.
