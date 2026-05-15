---
name: Eve box process supervision (PM2 + systemd + cron)
description: Which long-running services survive reboot on the Eve box and how — PM2 handles Ollama/cloudflared/sharedbrain; systemd handles cron + pm2-eve; Workspace MCP is Claude Code's stdio child
type: reference
originSessionId: 802209e5-5b97-40e7-9a67-a7bc40093c31
---
Eve box (GMKtec NucBox, Ubuntu) persistent-process map — verified 2026-04-22:

**systemd (system level, auto-start via `systemctl is-enabled`):**
- `cron.service` — enabled. Runs all pulse/BTS/backup cron entries. See `crontab -l` on user `eve`.
- `pm2-eve.service` — enabled. Starts the PM2 daemon on boot as user `eve`.

**PM2 (user-level process supervisor, launched by pm2-eve.service):**
- `cloudflared` — tunnel (details TBD, didn't inspect closely).
- `ollama` — `/home/eve/.local/bin/ollama serve` on `127.0.0.1:11434`. Local LLM server (qwen2.5:7b etc.). PM2 respawns it on crash.
- `sharedbrain` — Node.js app (the L&R SharedBrain) running as a PM2-managed fork process.
- `whatsapp-bridge` — added 2026-05-02. WhatsApp gateway service.
- `pm2 list` shows current state; `~/.pm2/dump.pm2` is the saved process list that PM2 restores on boot.

**Hardware safety (verified 2026-05-02 per Alex):**
- *UPS attached* — the eve box runs through a UPS, so brief power blips don't kill it. No `apcupsd`/`nut` software hooks installed yet, so no graceful auto-shutdown on extended outage — but bridges short cuts.
- *Encrypted USB stick for local backups* — Transcend JetFlash 7.5 GB on `/dev/sdb1`, LUKS-encrypted (`crypto_LUKS` filesystem). Lives on the box; unlocked + mounted on demand for local backups. Complements the nightly Drive backup (off-site).
- No RAID on the box itself (single 238 GB SSD as `/dev/sda`).

**systemd --user (eve's account, `loginctl` linger enabled 2026-04-22):**
- Currently no Eve-specific user services. Linger is on, so future user services run without an active login session.

**Claude Code stdio children (on-demand, not supervised):**
- `google_workspace_mcp/main.py` — spawned by Claude Code when an MCP session starts; exits when that session ends. Do not systemd-ify this — it's not a daemon, it's a stdio JSON-RPC child.

**How to apply:**
- Before adding a systemd unit for a long-running process, check `pm2 list` and the PM2 dump — it may already be supervised. Duplicate supervision causes port/startup races.
- On reboot audit: only the two `systemd is-enabled`'d units (cron + pm2-eve) strictly matter for persistence. Everything else (Ollama, cloudflared, sharedbrain, cron jobs) flows from those two.
- Workspace MCP is stdio, not HTTP — don't try to wrap it in a service; it expects a client to connect via stdin/stdout.
