# E.V.E. — Vendor Layer

Platform-layer files for **E.V.E.** (Evolving Virtual Entity) — the AI-teammate technology offered by *Evolving Virtual Entity LLC* (Washington, in formation).

## What this repo is

This repo holds the **vendor layer**: files that are identical across every customer's box. Each customer's *instance* — name, persona, voice, vault content, credentials — lives on their own box in a `.gitignore`'d customer layer.

### Three-layer model

| Layer | Owner | Examples |
|---|---|---|
| **Vendor company** | Evolving Virtual Entity LLC | This repo. The business behind the platform. |
| **Platform / product** | This repo | `CLAUDE.base.md`, vendor memory files, eve-tools scripts, bridges, install + update scripts. Pushed to all customer boxes. |
| **Instance** | Each customer | Their name (L&R picked *Eve*), persona, voice, vault, OAuth tokens. Never committed here. |

L&R's instance is *Eve* — Vietnamese American, Bayard Street backstory, Amy voice, Saigon rooftop selfie. None of that ships in this repo; it lives only on the L&R box's `.gitignore`'d customer layer.

## Layout (current — Phase 1)

```
.
├── CLAUDE.base.md          # platform-layer Claude rules
├── assemble-claude.sh      # cat user.md + base.md -> CLAUDE.md
├── memory/vendor/          # 21 universal memory files (behavioral rules, tool refs)
├── README.md
└── .gitignore              # customer-layer paths
```

## Roadmap

Tracked in the L&R vault at `02-Projects/Eve-Backlog/Integrations.md`.

| Phase | Status |
|---|---|
| 1 — File-split prep (CLAUDE.md + memory dir) | ✓ done 2026-05-15 |
| 2 — Bootstrap installer + this git repo | in progress — initial commit is the Phase 1 deliverables |
| 2.5 — Customer dashboard + admin console | pending |
| 3a — Containerize (shipped box) | future |
| 3b — Cloud-hosted SaaS | future |
| 3c — Vendor self-hosted multi-instance | future |

## Where things land on a customer box

| Repo file | Customer box path |
|---|---|
| `CLAUDE.base.md` | `~/EveBrain/CLAUDE.base.md` |
| `assemble-claude.sh` | `~/.local/eve-tools/assemble-claude.sh` |
| `memory/vendor/*.md` | `~/.claude/projects/-home-eve-EveBrain/memory/vendor/` |

The `eve-update.sh` script (Phase 2, not yet committed) handles the copy + assemble + service restart.

## Conventions

- All files in this repo are vendor-layer. **No customer specifics.** If a memory file or rule mentions L&R, Alex, Shawn, or any specific email/space ID, it belongs in the customer's instance layer, not here.
- Commits should be small and reversible. The fleet pulls from `main`; rollback = `git revert`.
- Customer-layer paths are enforced by `.gitignore` — if you find yourself fighting it, the file probably shouldn't be in this repo.
