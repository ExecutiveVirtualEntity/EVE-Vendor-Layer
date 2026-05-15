# bridges/sharedbrain

Node.js web server that exposes the SharedBrain UI (chat + file uploads + Drive proxy) to the public web via a Cloudflared tunnel.

## What it is

Customer-facing web UI for a customer's E.V.E. instance. Runs as a PM2 process on :3000, fronted by `<subdomain>.evolvingvirtualentity.com` via cloudflared.

## Files

| File | Purpose |
|---|---|
| `server.js` | Express app — chat endpoint, file upload, Drive proxy, websocket |
| `gdrive-auth.js` | OAuth handler for Google Drive |
| `gdrive-server.js` | Drive read/write helpers |
| `index.html` | Single-page web UI |
| `logo.jpg` | Branding (L&R logo on the L&R instance; replace per-customer) |
| `package.json` + `package-lock.json` | Deps: express, googleapis, node-fetch, node-pty, ws |

## Customer-layer (NOT in this repo)

- `node_modules/` — `npm install` regenerates from package.json
- `credentials.json` — Google OAuth client credentials (per-customer)
- `gdrive-token.json` — Refresh token (per-customer)
- `.claude/` — Claude Code state (per-instance)

## TODO — sanitize before customer #2

- `server.js` has L&R-specific references — same templatization pattern as `eve-tools/` (env vars from `~/.config/eve/instance.env`)
- `logo.jpg` is the L&R logo — replace per-customer in the install flow, or read path from env
- `index.html` may have L&R-specific branding — audit

PM2 startup (managed by install.sh's PM2 config):

```bash
pm2 start server.js --name sharedbrain --cwd /home/eve/remote
```

(Path TBD — install.sh will pick a canonical location like `~/sharedbrain/` instead of `~/remote/`.)
