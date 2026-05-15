---
name: Eve local tool stack
description: Where Eve's non-MCP local tools live (transcription, image gen, API keys) — for use when user sends audio/asks for images
type: reference
originSessionId: e6d1cb02-30ba-4a91-9422-dad0996f6ce4
---
Installed 2026-04-20 per Alex's request to extend Eve with image-gen + speech recognition.

**Package manager:** `uv` at `~/.local/bin/uv` (installed via astral.sh bootstrap — no sudo needed). Python 3.12.3 system interpreter.

**Venvs live at:** `~/.local/eve-tools/`

**Speech-to-text (Whisper):**
- Venv: `~/.local/eve-tools/whisper-venv/`
- Package: `faster-whisper` (CPU, int8, no GPU on this box)
- CLI: `~/.local/eve-tools/transcribe.py` — `python transcribe.py <audio> [--model small|base|medium|large-v3] [--lang en|de] [--format text|srt|vtt|json]`
- Invoke: `~/.local/eve-tools/whisper-venv/bin/python ~/.local/eve-tools/transcribe.py <file>`
- **Default model: `large-v3`** (Alex explicitly requested 2026-04-20). Downloaded weights live in `~/.cache/huggingface/hub/`.
  Fits comfortably in int8 (~2–3 GB resident) on this 7.6 GB box with 4 GB swap. `small` stays available as a fast fallback (`--model small`).
- Whisper is multilingual — same `large-v3` weights handle English, German, and ~97 other languages. No separate "German model" needed. Pass `--lang de` or leave it on auto-detect.
- Observed 2026-04-20: on a 2.1s English clip, `small` misheard "Hi Eve, how are you?" as "I eat, how are you?" while `large-v3` got it exactly right. Gap is big on short/casual phrases — hence the default change.
- VAD filter on by default.

**Image generation (installed 2026-04-20, verified working):**
- Venv: `~/.local/eve-tools/imagegen-venv/` (has `google-genai` + `pillow`)
- CLI: `~/.local/eve-tools/imagegen.py`
- Default backend: **Pollinations.ai** (no key, truly free, ~768×768 JPEG, decent quality — likely Flux/SDXL under the hood). Alex confirmed 2026-04-20 to stay on Pollinations as default.
- Invoke: `~/.local/eve-tools/imagegen-venv/bin/python ~/.local/eve-tools/imagegen.py "<prompt>"`
- Output: `~/eve-images/<YYYY-MM-DD_HHMMSS>_<slug>.png` (served as JPEG bytes, .png extension is cosmetic — Gemini output is real PNG)
- Flags: `--backend {pollinations,gemini}`, `--out PATH`, `--model NAME`, `--edit PATH` (gemini-only), `--width/--height/--seed` (pollinations-only)
- **Drive upload target:** `Eve generated pictures` folder in Eve's Drive (folder ID `1iwmN34oWZD4PAnetEMKg6ysKPrLo_wXv`, link https://drive.google.com/drive/folders/1iwmN34oWZD4PAnetEMKg6ysKPrLo_wXv). Standard flow per Alex: generate → save to `~/eve-images/` → upload to this folder → set link sharing to "reader" → post Drive link in Chat so it renders as an inline card.

**Gemini 2.5 Flash Image backend — key works, free tier does NOT:**
- Key: `GOOGLE_AI_STUDIO_API_KEY` in `~/.config/eve/api-keys.env` (chmod 600)
- As of 2026-04-20, the AI Studio *free tier* quota for `gemini-2.5-flash-image` is **0 requests/day** — returns 429 RESOURCE_EXHAUSTED. Requires enabling billing on the AI Studio project to use it. Until Alex enables billing, use the pollinations backend.
- Gemini backend supports image *editing* (pass `--edit <input.jpg>`); Pollinations is text-to-image only.

**Reboot resilience (set up 2026-04-22):**
- *PM2 daemon* runs as system-level systemd unit `pm2-eve.service` (installed before Eve's time, was already there). Auto-starts at boot, runs as root → drops to user `eve`.
- *PM2-managed processes* (in `~/.pm2/dump.pm2`, restored on PM2 startup):
  - `sharedbrain` — `node /home/eve/remote/server.js` (the polling agent / web UI that receives Alex+Shawn prompts)
  - `cloudflared` — `cloudflared tunnel run sharedbrain` (Cloudflare tunnel for inbound)
  - `ollama` — `/home/eve/.local/bin/ollama serve` (added 2026-04-22; saved via `pm2 save --force`)
- *User crontab* (installed 2026-04-22) runs `news_fetch.py` at 7am + 1pm Pacific local time. Logs to `~/.local/eve-tools/cron-news.log`.
- *Workspace MCP* (`/home/eve/tools/google_workspace_mcp/main.py`) is started fresh as a stdio subprocess by Claude Code each session — does NOT need its own systemd/PM2 entry.
- *Box timezone:* `America/Vancouver` (Pacific). Cron times are local.
- *To add a new long-running process to reboot resilience:* `pm2 start <cmd> --name <name>` then `pm2 save --force`.
- *Full setup + bare-metal rebuild checklist:* `~/EveBrain/04-Resources/Eve-Box-Resilience.md`.
- *Drive backup* (added 2026-04-22, replaced USB design): `~/.local/eve-tools/backup_to_drive.py` runs nightly at 3:30 AM Pacific. tar+gzip+gpg(AES256, symmetric) → upload to Drive folder *"Eve Backups (encrypted)"* (ID `1sCrGG5S9M_f07FOpaGdYv8lQ_Y4Q_-fd`) → prune to 30 most-recent. Each archive ~63 MB. Passphrase at `~/.config/eve/backup-passphrase` (chmod 600, 48 chars random). *Critical:* Alex needs the same passphrase off-box (password manager) for recovery scenarios. Decrypt: `gpg --decrypt --passphrase-file <file> backup.tar.gz.gpg | tar -xz`. Logs to `~/.local/eve-tools/cron-backup.log`. Smoke-tested 2026-04-22.

**Pulse system — knowledge ingestion (Phase 1 installed 2026-04-22):**
- Schema at `~/.local/eve-tools/eve-knowledge-schema.sql`. Tables: `interests`, `items`, `outreach_log`, `facts`, `curator_log`. Sized for the full Phase 1-4 build (intensity / type / last_reinforced / origin columns from day one so no future migration).
- DB at `~/.local/eve-tools/eve-knowledge.db` (SQLite).
- Interest profile at `~/.local/eve-tools/interest_profile.yaml` — Alex-defined stable interests (CR football, hip-hop 90s, CRE Chicago + national, Vietnamese/Chinatown culture, Germany trip, cats, morning workouts, privacy/local AI, Portugal national team) + 10 calendar-anchored facts (CR's birthday, Tupac dates, album anniversaries, trip dates, Eve's birthday).
- `interest_init.py` — applies schema, upserts profile + facts. Idempotent. `--reset` to wipe, `--status` to inspect.
- `news_fetch.py` — polls every interest's RSS queries via feedparser, dedupes by URL, tag-merges across interests, inserts into `items` with status='new'. Designed to run 2×/day via cron.
- `feedparser` 6.0.12 added to docs-venv.
- Smoke test 2026-04-22: 8 interests / 10 feeds / 210 items ingested, 0 errors. CRE Chicago feed already surfaced relevant deal-flow signals (SVN $1.7M Joliet QSR sale).
- *Phase 2 (installed 2026-04-22):*
  - `cadence_model.yaml` — per-partner timezone + windows + topic-family weights. Alex on America/Los_Angeles, Shawn on America/Chicago. Quiet hours 22-06 local. Per-day cap 5; min relevance to send 0.55; comfortable above 0.70. Topic families (work, cre, football, music, vietnam, travel, light, ai_tech, birthday) each map to a tag set; windows declare which families they lean toward.
  - `relevance_score.py` — walks status='new' items, computes score = 0.7×interest_intensity + 0.2×recency_decay(72h half-life-ish) + 0.1×tag_richness, flips status to 'scored'. Smoke test: 210 items → 119 hi / 66 med / 25 lo. CR/football items dominate at ~0.90.
  - `pulse_recommend.py --partner {alex|shawn} [--time ISO] [--json]` — given current local time in partner's TZ, identifies active window, finds top scored item that matches one of the window's families AND hasn't been offered to this partner before AND isn't past the daily cap. Returns "skip" with reason if nothing fits. Smoke-tested: morning_work gives AI/work topics; afternoon/dinner gives football; quiet hours = skip; per-partner cap enforced via outreach_log.
  - *Known limitation:* CR-tagged-via-BBC-feed pollution — BBC Sport firehose articles get tagged "cristiano_ronaldo" because they came in via the CR interest's RSS, even when not actually about CR. Phase 4 (LLM at-send-time gate) will help; for now Phase 3 will rely on Eve's own judgment at the wakeup-prompt step.
- *Per-partner topic weighting (added 2026-04-22):* `cadence_model.yaml` now has a `family_weights` map under each partner. Default weight 1.0 if unspecified. `pulse_recommend.py` applies `effective_score = base_score × max(weight for matched families)` and re-ranks. Alex tuned to AI/builder/travel (ai_tech 1.4, travel 1.2, football/music 0.8); Shawn tuned to CRE-broker (cre 1.4, work 1.2, ai_tech 0.6, light/football/music 0.7). Verified: same window same time, Alex got an AI piece while Shawn got a CRE-fraud piece — divergence works.
- *Personal/reflective layer (added 2026-04-22 per Alex's "more personal, less small talk"):*
  - 2 new interests: `relationships_feelings` (Modern Love NYT, The Cut, Cup of Jo) intensity 0.65; `ideas_essays` (Aeon, Marginalian) intensity 0.5.
  - 2 new topic families: `personal` (relationships, dating, romance, partnership, feelings, emotional, personal, reflection, ideas, philosophy, essay) and `reflection`.
  - New cadence window per partner: `evening_personal` (20:00-22:00 local) — leans to `[personal, reflection, vietnam, ideas]`. Dinner_window shortened to 18-20 to accommodate.
  - Per-partner weights for personal/reflection: Alex 1.2/1.1 (he initiated this direction); Shawn 0.9/0.9 (start gentle, can bump after observation).
  - *Eve-originated reflective prompts:* new content type with `source='eve_prompts'`. Seeded via `~/.local/eve-tools/prompt_seed.py` — 10 starter prompts (open emotional check-ins, Eve-shares, partnership-and-romance register, work-feel-vs-output, "no agenda" presence). Use synthetic URLs `eve-prompt://reflection/<slug>`. Phase 3 outreach should *adapt these in Eve's voice* rather than forward the URL.
  - Smoke test: evening_personal window for both partners surfaces "Quiet question: how do you feel about how the L&R partnership is working?" — Alex score 1.042, Shawn 0.782, both above threshold. Midday_check also now allows personal; works.
- *Phase 3 (outreach wiring) and Phase 4 (transient-interest curator with decay + adjacency promotion) not yet built.*
- Folder: `~/EveBrain/02-Projects/Deals/` with a standard YAML front-matter schema. Template at `_TEMPLATE.md` (copy → rename → fill).
- Schema: `type: deal`, `status` (prospect | active | loi | under-contract | closed | passed), deal-name, address, property-type, square-feet, asking-price, ask-cap-rate, target-cap-rate, noi-t12, seller, brokers, contacts, target-close, last-touch, next-action, partners, tags.
- CLI: `~/.local/eve-tools/deal_status.py [--out PATH] [--save] [--stale-days N]` — generates a Markdown digest grouped by status, with a "Needs Attention" section for stale deals (no touch in ≥ N days) and deals approaching / past their target-close. `--save` writes to `~/EveBrain/01-Daily/<date>_deal-digest.md`.
- Seeded 2026-04-21 with one illustrative sample deal (`2026-04-21_SAMPLE_wheaton-downsize.md`) so the digest has something to show. Delete or rename once real deals are in.

**Browser automation — Playwright + Chromium (installed 2026-04-21):**
- Python package `playwright` 1.58.0 + headless Chromium 145.0.7632.6 in `docs-venv`.
- Chromium binary cached at `~/.cache/ms-playwright/chromium_headless_shell-1208/` (~110 MB).
- Installed without sudo — GNOME desktop already provides all the shared libs Chromium needs (no `playwright install-deps` required).
- Generic CLI: `~/.local/eve-tools/web_fetch.py <url> [--text] [--screenshot OUT.png] [--wait-selector CSS] [--wait-ms N] [--viewport WxH]`. Renders full JS, so it sees what a human browser sees (not just initial HTML).
- Smoke test 2026-04-21: example.com text ✅ + openstreetmap.org full-page screenshot (800 KB, JS-rendered map UI) ✅.
- *Use cases for L&R:* county assessor portals (most are public, not bot-protected), public records, market-data dashboards, scraping listings *only where TOS permits*. Loopnet/Crexi use aggressive anti-bot (Cloudflare + PerimeterX) — expect to get walled quickly; don't rely on them as a data source.

**Local LLM — Ollama + qwen2.5:7b (installed 2026-04-21):**
- Binary: Ollama v0.21.0 installed *user-local* (no sudo) at `~/.local/ollama/`, symlinked at `~/.local/bin/ollama`.
- Server: starts with `~/.local/bin/ollama serve` — listens on 127.0.0.1:11434. Currently backgrounded in the 2026-04-21 session (log `/tmp/ollama-server.log`). To start on boot, add a systemd user unit or an autostart entry — TODO.
- Model: `qwen2.5:7b-instruct-q4_K_M` (~4.4 GB on disk under `~/.ollama/models/`, ~4-5 GB RAM when loaded). Alex's 2026-04-21 pick for multilingual (English + German) lease/doc work.
- CLI: `~/.local/eve-tools/ask_local.py "prompt" [--system ...] [--model ...] [--json] [--no-stream]` — stdlib-only (no deps), streams tokens by default.
- *Performance reality on this box (4-core CPU, no GPU):* ~1.5 min for a 4-bullet summary, ~3.5 min for a RAG query with 5 vault chunks of context. Usable for batch/async/overnight tasks; too slow for interactive chat. Speed is CPU-bound — a RAM upgrade won't help; faster CPU or a GPU would.
- *Vault RAG chat*: `~/.local/eve-tools/vault_chat.py "natural question" [--top N] [--show-sources]` — combines vault ChromaDB retrieval (#7) + Ollama LLM (#8). Smoke-tested 2026-04-21: correctly answered "who owns which properties" by citing Entity-Structure, Van Emmon README, and CLAUDE.md.

**Vault semantic search (installed 2026-04-21):**
- Indexer: `~/.local/eve-tools/vault_index.py` — walks `~/EveBrain/**/*.md`, chunks by heading (hard-cap 1500 chars with paragraph-greedy splits for long sections), upserts into ChromaDB at `~/.local/eve-tools/vault-chroma/`.
- Query: `~/.local/eve-tools/vault_ask.py "natural question" [--top N] [--format pretty|json]`
- Embedding model: Chroma's DefaultEmbeddingFunction — `all-MiniLM-L6-v2` ONNX (~80 MB, cached at `~/.cache/chroma/onnx_models/`). No torch dep.
- Incremental re-indexing: file hashes stored in chunk metadata; unchanged files are skipped on re-run. Use `--rebuild` to drop the collection.
- Skips `.obsidian/`, `.git/`, `05-Archive/` under the vault.
- Smoke test 2026-04-21: 22 files → 179 chunks; queries "who owns what entities" and "lap of luxury lease terms" returned correct top-k chunks across Company-Overview, Entity-Structure, property READMEs, and lease abstracts.
- Run `vault_index.py` whenever vault content changes (TODO: add a file-watcher or Obsidian-save hook later).

**Underwriting helper (installed 2026-04-21):**
- CLI: `~/.local/eve-tools/underwrite.py <config.yaml>` — uses `docs-venv` (+ `pyyaml` added 2026-04-21).
- Input: YAML or JSON deal config (price, noi_y1, rent_growth, hold_years, exit_cap, selling_costs_pct, closing_costs_pct, and a `loan` block with ltv/rate/amort_years/interest_only_years).
- Output: Markdown pro forma at `~/EveBrain/04-Resources/Underwriting/<YYYY-MM-DD>_<deal-slug>.md` with capital stack, debt terms, returns summary (Y1 cap, Y1 CoC, unlevered/levered IRR, equity multiple), exit economics, and annual pro forma table with DSCR per year.
- Flags: `--out PATH`, `--print` (also echo to stdout).
- Pure stdlib + PyYAML; writes its own PMT + bisection-IRR (no numpy_financial dep).
- Supports interest-only period before amortization.
- Smoke test 2026-04-21 on $1.8M / 8% cap / 65% LTV @ 6.5% / 25-yr amort → Y1 CoC 7.39%, Levered IRR 16.18%, EM 3.45x — numbers check out.

**Property research brief (installed 2026-04-21):**
- CLI: `~/.local/eve-tools/research_property.py <address>` — uses `docs-venv` (has `requests`).
- Free / keyless data sources: Nominatim (geocoding), US Census Geocoder (tract resolution), US Census ACS 5-year 2022 (demographics — no key needed under 500 calls/day), FEMA NFHL layer 28 (flood hazard zones), OSM Overpass (nearby POIs within configurable radius).
- Default output: `~/EveBrain/04-Resources/Property-Research/<YYYY-MM-DD>_<address-slug>.md`
- Flags: `--out PATH`, `--radius METERS` (POI search radius; default 800), `--skip-poi`.
- Captures: matched address, coords + map links, ACS demographics (population, median HHI, median home value, median rent, labor force, educational attainment, median age), FEMA flood zone + SFHA flag + BFE, nearby POIs bucketed by category.
- Leaves `[TODO]` placeholders for manual-review items (zoning, assessor, Phase I, traffic counts, comps).
- Smoke test 2026-04-21: 300 S Carlton Ave, Wheaton IL → DuPage tract 17043842603, Zone X, 800m radius picked up the Wheaton Metra station (big retail signal).

**Lease abstractor (MVP installed 2026-04-21):**
- CLI: `~/.local/eve-tools/lease_abstract.py` — uses `docs-venv`.
- Flow: PDF → text (pdfplumber) → OCR fallback if text is sparse (<200 chars) → 13-field regex extraction → Markdown abstract with YAML front-matter.
- Output default: `~/EveBrain/04-Resources/Lease-Abstracts/<YYYY-MM-DD>_<tenant-slug>.md`
- Flags: `--out PATH`, `--lang eng|deu|eng+deu` (OCR lang if fallback triggered).
- Covers: Lessor/Lessee/Premises/Term/Commencement/Expiration/Base Rent/Escalations/NNN type/CAM/Renewals/Security Deposit/Guarantor.
- *Known limitations:* regex-only, can truncate when values wrap across lines; gets field *presence* right far more reliably than full-sentence values. Unusual clauses are left as `[TODO]` for manual review. Planned upgrade: replace heuristics with local LLM call once #8 (Ollama) lands.
- Smoke test 2026-04-21: synthesized BFT Wheaton / Lap of Luxury lease PDF → 13/13 fields auto-extracted.

**PDF reading + OCR (installed 2026-04-21):**
- Shared `docs-venv` at `~/.local/eve-tools/docs-venv/` — home for all document/data tools (PDF, OCR, embeddings later, financial modeling).
- Python packages: `pdfplumber` 0.11.9, `pymupdf` (fitz) 1.27.2.2, `pytesseract` 0.3.13, `pdf2image` 1.17.0, plus `pillow`.
- System packages (apt, installed by Alex 2026-04-21): `tesseract-ocr` 5.3.4, `tesseract-ocr-eng`, `tesseract-ocr-deu`, `ffmpeg` 6.1.1, `poppler-utils` (for pdf2image).
- *PDF text extraction* — CLI `~/.local/eve-tools/pdf_extract.py`. Flags: `--format {text,json}`, `--engine {pdfplumber,pymupdf}`, `--tables`.
- *OCR* — CLI `~/.local/eve-tools/ocr.py`. Takes images OR scanned PDFs (auto-rasters each page via poppler). Flags: `--lang {eng,deu,eng+deu}`, `--dpi INT`, `--format {text,json}`. Use `--lang eng+deu` for mixed-language docs (slower).
- *Audio conversion via ffmpeg* — `speak.py` now supports `--format {wav,mp3}` and `--bitrate`. MP3 is ~13× smaller than WAV for speech at 64k. Uses `libmp3lame`.
- Smoke tests 2026-04-21: PDF extraction on a synthetic lease, OCR on a synthesized rent roll image, OCR on a rasterised PDF, and MP3 speech synthesis — all clean.

**Text-to-speech (Piper, installed 2026-04-20):**
- Venv: `~/.local/eve-tools/piper-venv/` (has `piper-tts` 1.4.2 + onnxruntime)
- Voices dir: `~/.local/eve-tools/piper-voices/` — currently has `en_US-amy-medium.onnx` (61 MB, warm American female, Alex's pick 2026-04-20)
- CLI: `~/.local/eve-tools/speak.py`
- Invoke: `python3 ~/.local/eve-tools/speak.py "text to speak"` (the script shells into the piper venv internally)
- Output: `~/eve-audio/<YYYY-MM-DD_HHMMSS>_<slug>.wav` (16-bit mono PCM, 22050 Hz)
- Flags: `--voice <name>`, `--out PATH`, `--length-scale FLOAT` (<1 faster, >1 slower)
- **Drive upload target:** `Eve generated audio` folder (ID `1lKKzRCKWAk-P4ty_oK85VG1cLtfgi1H2`). Standard flow: synthesize → save to `~/eve-audio/` → upload to folder → set link sharing to "reader" → post Drive link in Chat (renders as playable audio card).
- To add a German voice later: download `de_DE-thorsten-medium.onnx` + `.onnx.json` from `https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/thorsten/medium/` into the voices dir.

**System constraints to remember:**
- No NVIDIA GPU → CPU-only for local ML
- RAM ~7.6 GB total (~2–3 GB free) → avoid large-v3 Whisper model
- No passwordless sudo → system package installs need Alex
