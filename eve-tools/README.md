# eve-tools/

Platform-layer scripts. install.sh copies these to `~/.local/eve-tools/` on every customer box. Cron entries point here.

## What's in here

| Script / file | Purpose |
|---|---|
| `ask_local.py` | Ollama wrapper for local LLM queries (sensitive doc work) |
| `assemble-claude.sh` | (at repo root) cat CLAUDE.user.md + CLAUDE.base.md → CLAUDE.md |
| `backup_to_drive.py` | Nightly encrypted (AES-256 + GPG) backup to Google Drive, 30-day rolling |
| `backup_to_usb.py` | Encrypted local backup to USB drive (mirror of Drive backup) |
| `bts_sweep.py` | Build-to-suit deal-sourcing sweep + daily digest |
| `chat_send_audio.py` | Upload audio messages to Google Chat |
| `daily_brief.py` | 7am + 2pm daily brief (WhatsApp + Chat) |
| `deal_status.py` | CRE deal status updates |
| `eve-knowledge-schema.sql` | Schema for the knowledge DB (rows are customer-layer, schema is vendor) |
| `imagegen.py` | Gemini image generation wrapper |
| `interest_init.py` | (re)load interests from `interest_profile.yaml` (customer-supplied) into the knowledge DB |
| `lease_abstract.py` | Lease PDF → structured abstract |
| `news_fetch.py` | RSS / news ingestion (driven by customer-supplied `interest_profile.yaml`) |
| `ocr.py` | Tesseract wrapper for image → text |
| `pdf_extract.py` | PDF text extraction |
| `plaud_client.py` | Plaud cloud API client |
| `plaud_ingest.py` | Hourly pull from Plaud + Whisper transcription + Ollama analysis + vault write |
| `prompt_seed.py` | Internal helper for prompt assembly |
| `pulse_curator.py` | Daily curator pass over news+events |
| `pulse_outreach.py` | (paused) Outreach scheduler |
| `pulse_recommend.py` | Recommend what to send/do, given the cadence model |
| `relevance_score.py` | Score news items against interest profile |
| `research_property.py` | Parcel / zoning / comps research |
| `speak.py` | Piper TTS wrapper |
| `transcribe.py` | Whisper STT wrapper |
| `underwrite.py` | CRE underwriting model |
| `vault_ask.py` | One-shot vault question (uses Chroma RAG) |
| `vault_chat.py` | Interactive vault chat session |
| `vault_index.py` | Build/refresh Chroma index over the vault |
| `web_fetch.py` | HTTP fetch utility |

## Customer-supplied configs (NOT in this repo)

Some scripts read YAML / DB / cache files that live in the *instance layer*, not here:

- `cadence_model.yaml` — outreach pacing + topic families (per-customer)
- `interest_profile.yaml` — RSS sources + interests (per-customer)
- `eve-knowledge.db` — rows are per-customer (schema is in this repo)
- `plaud-cache/`, `plaud-state/` — runtime state (per-customer)
- `vault-chroma/` — RAG index built from the customer's vault

install.sh creates the empty dirs; the dashboard (Phase 2.5) handles populating the configs.

## Sanitization — templatizing customer-specific strings

Vendor-layer scripts must NOT contain hardcoded customer-specific strings (emails, vault path, Chat space IDs, WhatsApp JIDs, etc.). Each customer instance reads its own values from `~/.config/eve/instance.env` (populated by the onboarding dashboard in Phase 2.5; hand-edited for now).

### Pattern

**Python scripts:**
```python
from eve_config import EVE_INSTANCE_EMAIL, EVE_VAULT, get_team_members
# Use the constants directly. eve_config raises EveConfigError at import
# time if a required key is missing — fail loud, never silently fall back
# to a hardcoded value.
```

**Shell scripts:**
```bash
[[ -f "${HOME}/.config/eve/instance.env" ]] && source "${HOME}/.config/eve/instance.env"
VAULT="${EVE_VAULT:-${HOME}/EveBrain}"  # safe default; required keys should NOT fall back
```

Schema: `eve-tools/instance.env.example` (canonical) + `eve-tools/eve_config.py` (Python loader).

### Progress (13 scripts + 1 in repo root)

| Script | L&R hits | Status |
|---|---|---|
| `assemble-claude.sh` (repo root) | 1 (VAULT path) | ✓ sanitized — falls back to `${HOME}/EveBrain` if `instance.env` missing |
| `backup_to_drive.py` | 2 (creds file path + vault path) | TODO |
| `bts_sweep.py` | 0 in this grep (broader pass may find more) | re-audit |
| `chat_send_audio.py` | 1 (just docstring example — likely fine) | re-audit |
| `daily_brief.py` | 5 (Alex WA JID, Chat space, 3 team emails) | TODO — biggest |
| `deal_status.py` | 0 in this grep | re-audit |
| `lease_abstract.py` | 0 in this grep | re-audit |
| `plaud_ingest.py` | 0 in this grep | re-audit |
| `pulse_outreach.py` | 2 (Eve email twice) | TODO |
| `research_property.py` | 2 (docstring example + User-Agent) | TODO — User-Agent matters |
| `underwrite.py` | 0 in this grep | re-audit |
| `vault_chat.py` | 1 (one hit, line not surfaced) | re-audit |
| `vault_index.py` | 0 in this grep | re-audit |

Plus `bridges/sharedbrain/server.js` — separate sanitization needed (Node, not Python).

### Conversion checklist for each script

1. Grep the script for: `labrasseur`, `alexander\.reich`, `shawn\.labrasseur`, `EveBrain`, `spaces/AAQA`, `spaces/xirOw`, `133324425179144`, `L&R`, `Van Emmon`, `Yorkville`, `UA 907`, `UA 8718`, any project/property name
2. For each hit, replace with `eve_config` constant or `os.getenv` + assertion
3. If the script needs a new config key, add it to `instance.env.example` and `eve_config.py`
4. Test locally with an instance.env in place
5. Mark ✓ in the table above + commit
