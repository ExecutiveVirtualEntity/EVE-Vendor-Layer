#!/usr/bin/env python3
"""eve_sync.py — pull this box's config from the dashboard.

Runs every minute via cron. Reads the box's registration token, POSTs it
to the dashboard's /api/box/sync endpoint, and applies whatever the
dashboard sends back to ~/.config/eve/instance.env.

Boxes register themselves into the dashboard's inventory at install time
(see install.sh). Once an operator binds a box to a customer instance via
/admin, the next eve_sync run pulls the personalization the customer
configured on /app (persona name, voice, vault path, ...) and writes it
to instance.env. PM2 services restart if anything material changed.

Exit codes:
  0  — sync ran successfully (no-op or changes applied)
  1  — config error (no token file, malformed token, etc.)
  2  — network or dashboard error (will retry next tick — non-fatal)

This script intentionally has zero non-stdlib dependencies so it can run
on a fresh box before any venv is wired up. urllib.request only.
"""

from __future__ import annotations

import json
import logging
import os
import pathlib
import subprocess
import sys
import urllib.error
import urllib.request

# ────────────────────────────────────────────────────────────────────────
# Paths and constants
# ────────────────────────────────────────────────────────────────────────

TOKEN_PATH = pathlib.Path.home() / ".config" / "eve" / "registration.token"
INSTANCE_ENV = pathlib.Path.home() / ".config" / "eve" / "instance.env"
LOG_PATH = pathlib.Path.home() / ".local" / "eve-tools" / "cron-sync.log"

DEFAULT_DASHBOARD = "https://dashboard.executivevirtualentity.com"
DASHBOARD_URL = os.environ.get("EVE_DASHBOARD_URL", DEFAULT_DASHBOARD)
SYNC_TIMEOUT_SECS = 15

# Keys eve_sync owns — these are overwritten from the dashboard payload
# on every successful sync. Any key not in this list is left alone, so
# operator-set values (credentials, machine-specific overrides, etc.)
# survive untouched.
DASHBOARD_OWNED_KEYS = {
    "EVE_INSTANCE_NAME",
    "EVE_VAULT",
    "EVE_VOICE_ID",
    "EVE_PORTRAIT_URL",
    "EVE_EXPIRES_AT",
    "EVE_INSTANCE_ACTIVE",
}

# ────────────────────────────────────────────────────────────────────────
# Logging
# ────────────────────────────────────────────────────────────────────────

LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    filename=str(LOG_PATH),
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("eve_sync")


# ────────────────────────────────────────────────────────────────────────
# instance.env read/write
# ────────────────────────────────────────────────────────────────────────


def read_env_file(path: pathlib.Path) -> dict[str, str]:
    """Parse a Bourne-style env file. Mirrors eve_config._load_env_file's
    rules: KEY=VALUE, optional quoting, comments allowed."""
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()
        if (val.startswith('"') and val.endswith('"')) or (
            val.startswith("'") and val.endswith("'")
        ):
            val = val[1:-1]
        out[key] = val
    return out


def write_env_file(path: pathlib.Path, current_text: str, updates: dict[str, str]) -> str:
    """Apply key=value updates to env-file text. Preserves comments,
    blank lines, key ordering, and any keys not in `updates`.

    Returns the new file contents (does NOT write to disk — caller
    decides whether the diff justifies a restart).
    """
    seen: set[str] = set()
    new_lines: list[str] = []
    for raw in current_text.splitlines():
        line = raw.rstrip("\n")
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            new_lines.append(line)
            continue
        key = stripped.partition("=")[0].strip()
        if key in updates:
            seen.add(key)
            val = updates[key]
            new_lines.append(f"{key}={_quote_if_needed(val)}")
        else:
            new_lines.append(line)
    # Append any updates that weren't present in the file
    extras = [k for k in updates if k not in seen]
    if extras:
        if new_lines and new_lines[-1].strip():
            new_lines.append("")
        new_lines.append("# --- managed by eve_sync (dashboard-owned) ---")
        for k in extras:
            new_lines.append(f"{k}={_quote_if_needed(updates[k])}")
    return "\n".join(new_lines) + "\n"


def _quote_if_needed(val: str) -> str:
    """Wrap in double quotes if the value contains spaces, tabs, $, #, or
    any char that would confuse a shell-style env reader."""
    if not val:
        return '""'
    if any(c in val for c in (" ", "\t", "$", "#", "'", '"', "\\")):
        # escape backslashes + double quotes, wrap in double quotes
        escaped = val.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return val


def atomic_write(path: pathlib.Path, content: str) -> None:
    """Write atomically via a temp file + rename. Preserves the file's
    existing permissions if it already exists; defaults to 0600 for new
    instance.env (it can hold sensitive identifiers)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    if path.exists():
        os.chmod(tmp, path.stat().st_mode)
    else:
        os.chmod(tmp, 0o600)
    tmp.replace(path)


# ────────────────────────────────────────────────────────────────────────
# Dashboard sync
# ────────────────────────────────────────────────────────────────────────


def read_token() -> str:
    if not TOKEN_PATH.exists():
        log.error("no registration token at %s; box not registered", TOKEN_PATH)
        sys.exit(1)
    tok = TOKEN_PATH.read_text(encoding="utf-8").strip()
    if not tok:
        log.error("registration token file is empty")
        sys.exit(1)
    return tok


def call_sync(token: str) -> dict:
    url = f"{DASHBOARD_URL.rstrip('/')}/api/box/sync"
    req = urllib.request.Request(
        url=url,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "eve-sync/1.0",
        },
        data=b"{}",
    )
    try:
        with urllib.request.urlopen(req, timeout=SYNC_TIMEOUT_SECS) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        log.warning("dashboard HTTP %s: %s", e.code, body[:200])
        if e.code == 401:
            log.error("dashboard rejected token — re-register this box via /admin")
            sys.exit(1)
        if e.code == 410:
            log.error("instance was deleted — wipe + re-register this box")
            sys.exit(1)
        sys.exit(2)
    except urllib.error.URLError as e:
        log.warning("dashboard unreachable: %s", e)
        sys.exit(2)
    except (TimeoutError, ConnectionError) as e:
        log.warning("dashboard timeout/connection error: %s", e)
        sys.exit(2)


def config_to_env_updates(config: dict) -> dict[str, str]:
    """Map BoxConfigPayload → instance.env key/value updates. Only the
    keys the dashboard owns (DASHBOARD_OWNED_KEYS) are populated.
    """
    persona = config.get("persona") or {}
    updates: dict[str, str] = {}
    name = persona.get("name") or ""
    if name:
        updates["EVE_INSTANCE_NAME"] = name
    vault = persona.get("vault_path") or ""
    if vault:
        updates["EVE_VAULT"] = vault
    voice = persona.get("voice_id") or ""
    if voice:
        updates["EVE_VOICE_ID"] = voice
    portrait = persona.get("portrait_url") or ""
    if portrait:
        updates["EVE_PORTRAIT_URL"] = portrait
    expires = config.get("expires_at") or ""
    if expires:
        updates["EVE_EXPIRES_AT"] = expires
    updates["EVE_INSTANCE_ACTIVE"] = "true" if config.get("active", True) else "false"
    return updates


def maybe_reload_services(changed_keys: set[str]) -> None:
    """Restart PM2 services if any restart-relevant key changed. We're
    conservative — restart on any dashboard-owned change since each
    script reads instance.env at boot and won't pick up a live edit."""
    if not changed_keys:
        return
    log.info("instance.env changed keys: %s", sorted(changed_keys))
    try:
        subprocess.run(
            ["pm2", "restart", "all", "--silent"],
            check=False,
            timeout=30,
            capture_output=True,
        )
        log.info("pm2 restart all fired")
    except FileNotFoundError:
        log.warning("pm2 not on PATH; skipping restart (services will pick up on next manual restart)")
    except subprocess.TimeoutExpired:
        log.warning("pm2 restart timed out (continuing)")


# ────────────────────────────────────────────────────────────────────────
# Entrypoint
# ────────────────────────────────────────────────────────────────────────


def main() -> int:
    token = read_token()
    response = call_sync(token)

    if not response.get("bound"):
        log.info("box registered but not bound to a customer yet — no config to apply")
        return 0

    config = response.get("config") or {}
    if not config:
        log.warning("response had bound=true but empty config; ignoring")
        return 0

    updates = config_to_env_updates(config)
    if not updates:
        log.info("dashboard returned no personalization values yet")
        return 0

    existing_text = INSTANCE_ENV.read_text(encoding="utf-8") if INSTANCE_ENV.exists() else ""
    existing_env = read_env_file(INSTANCE_ENV)

    # Compute what's actually changing — drives whether we need a restart
    changed = {k for k, v in updates.items() if existing_env.get(k) != v}
    if not changed:
        log.info("no changes (instance #%s)", config.get("instance_id"))
        return 0

    new_text = write_env_file(INSTANCE_ENV, existing_text, updates)
    atomic_write(INSTANCE_ENV, new_text)
    log.info("applied %d update(s) to %s", len(changed), INSTANCE_ENV)

    maybe_reload_services(changed)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 — top-level catchall, cron-safe
        log.exception("unexpected error: %s", e)
        sys.exit(2)
