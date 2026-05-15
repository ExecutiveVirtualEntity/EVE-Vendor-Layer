"""eve_config.py — load customer-layer config from ~/.config/eve/instance.env.

Vendor scripts that need customer-specific values (emails, vault path, Chat
space IDs, WhatsApp JIDs, etc.) import this module and read the constants.

Usage:
    from eve_config import EVE_INSTANCE_EMAIL, EVE_VAULT, get_team_members

Failure mode:
    Missing required vars raise EveConfigError at import time — fail loud,
    never silently fall back to a hardcoded value from a previous customer.

The lone exception is EVE_VAULT, which defaults to ~/EveBrain since that's
the canonical install location and a missing override is a non-issue.
"""

from __future__ import annotations

import os
import pathlib
from dataclasses import dataclass


CONFIG_PATH = pathlib.Path.home() / ".config" / "eve" / "instance.env"


class EveConfigError(RuntimeError):
    """Raised when required instance config is missing or malformed."""


def _load_env_file(path: pathlib.Path) -> dict[str, str]:
    """Parse a Bourne-style env file into a dict.

    Supports:
      - KEY=VALUE (no spaces around =)
      - "double-quoted" or 'single-quoted' values
      - ${VAR} expansion against already-loaded keys + os.environ
      - # comments + blank lines
    """
    if not path.exists():
        return {}

    out: dict[str, str] = {}
    with path.open() as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip()
            # Strip surrounding quotes
            if (val.startswith('"') and val.endswith('"')) or (
                val.startswith("'") and val.endswith("'")
            ):
                val = val[1:-1]
            # Expand ${VAR} against already-loaded values + os.environ
            val = os.path.expandvars(_expand_with(val, out))
            out[key] = val
    return out


def _expand_with(value: str, loaded: dict[str, str]) -> str:
    """Substitute ${KEY} where KEY is in `loaded`. os.path.expandvars handles
    the rest against process env."""
    for key, v in loaded.items():
        value = value.replace(f"${{{key}}}", v)
    return value


_env = _load_env_file(CONFIG_PATH)


def _req(key: str) -> str:
    val = _env.get(key) or os.environ.get(key)
    if not val:
        raise EveConfigError(
            f"Missing required config key '{key}'. "
            f"Add it to {CONFIG_PATH} (see eve-tools/instance.env.example for the schema)."
        )
    return val


def _opt(key: str, default: str | None = None) -> str | None:
    return _env.get(key) or os.environ.get(key) or default


# ─── Required identity ──────────────────────────────────────────────────────
# Each of these MUST be defined in instance.env — no silent fallback.
EVE_INSTANCE_NAME: str = _req("EVE_INSTANCE_NAME")
EVE_INSTANCE_EMAIL: str = _req("EVE_INSTANCE_EMAIL")
EVE_INSTANCE_DOMAIN: str = _req("EVE_INSTANCE_DOMAIN")
EVE_INSTANCE_COMPANY_SHORT: str = _req("EVE_INSTANCE_COMPANY_SHORT")

# ─── Vault path — safe default ──────────────────────────────────────────────
EVE_VAULT: str = _opt("EVE_VAULT", str(pathlib.Path.home() / "EveBrain")) or ""

# ─── Backup ─────────────────────────────────────────────────────────────────
EVE_BACKUP_CREDS_FILE: str = _opt(
    "EVE_BACKUP_CREDS_FILE",
    str(
        pathlib.Path.home()
        / ".google_workspace_mcp"
        / "credentials"
        / f"{EVE_INSTANCE_EMAIL}.json"
    ),
) or ""
EVE_BACKUP_FOLDER_ID: str | None = _opt("EVE_BACKUP_FOLDER_ID")
EVE_BACKUP_LABEL: str = _opt("EVE_BACKUP_LABEL", "EveBrain") or "EveBrain"

# ─── User-agent for outbound HTTP ──────────────────────────────────────────
EVE_USER_AGENT: str = _opt(
    "EVE_USER_AGENT",
    f"Eve/{EVE_INSTANCE_COMPANY_SHORT}/1.0 ({EVE_INSTANCE_EMAIL})",
) or ""


# ─── Team members ───────────────────────────────────────────────────────────
@dataclass(frozen=True)
class TeamMember:
    email: str
    name: str
    scopes: frozenset[str]
    personal_email: str | None
    whatsapp_jid: str | None
    chat_space: str | None


def _load_team() -> list[TeamMember]:
    """Read EVE_TEAM_N_* keys until a gap. N starts at 1."""
    members: list[TeamMember] = []
    n = 1
    while True:
        email = _env.get(f"EVE_TEAM_{n}_EMAIL")
        if not email:
            break
        name = _env.get(f"EVE_TEAM_{n}_NAME", email)
        scopes_raw = _env.get(f"EVE_TEAM_{n}_SCOPES", "")
        scopes = frozenset(s.strip() for s in scopes_raw.split(",") if s.strip())
        personal = _env.get(f"EVE_TEAM_{n}_PERSONAL_EMAIL") or None
        jid = _env.get(f"EVE_TEAM_{n}_WHATSAPP_JID") or None
        chat = _env.get(f"EVE_TEAM_{n}_CHAT_SPACE") or None
        members.append(
            TeamMember(
                email=email,
                name=name,
                scopes=scopes,
                personal_email=personal,
                whatsapp_jid=jid,
                chat_space=chat,
            )
        )
        n += 1
    return members


_TEAM = _load_team()


def get_team_members() -> list[TeamMember]:
    """Return all configured team members in declaration order."""
    return list(_TEAM)


def get_team_member_by_email(email: str) -> TeamMember | None:
    """Look up a teammate by primary OR personal email."""
    for m in _TEAM:
        if m.email == email or m.personal_email == email:
            return m
    return None


def get_team_member_by_name(name: str) -> TeamMember | None:
    """Look up a teammate by name (case-insensitive substring match)."""
    needle = name.lower()
    for m in _TEAM:
        if needle in m.name.lower():
            return m
    return None
