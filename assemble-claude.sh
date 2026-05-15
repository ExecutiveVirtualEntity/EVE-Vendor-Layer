#!/bin/bash
# Assemble CLAUDE.md from the vendor + customer source files.
# Phase 1 multi-tenancy prep (2026-05-15).
# Edit CLAUDE.base.md (vendor) or CLAUDE.user.md (customer), then run this script.

set -euo pipefail

# Customer-layer config (optional — script falls back to default vault path)
[[ -f "${HOME}/.config/eve/instance.env" ]] && source "${HOME}/.config/eve/instance.env"

VAULT="${EVE_VAULT:-${HOME}/EveBrain}"
BASE="$VAULT/CLAUDE.base.md"
USER="$VAULT/CLAUDE.user.md"
OUT="$VAULT/CLAUDE.md"

if [[ ! -f "$BASE" ]] || [[ ! -f "$USER" ]]; then
  echo "ERROR: missing source file(s). Expected $BASE and $USER." >&2
  exit 1
fi

{
  echo "<!-- AUTO-ASSEMBLED from CLAUDE.user.md + CLAUDE.base.md by ~/.local/eve-tools/assemble-claude.sh. Edit those files, NOT this one. -->"
  echo ""
  cat "$USER"
  cat "$BASE"
} > "$OUT"

echo "Wrote $OUT ($(wc -c < "$OUT") bytes) from:"
echo "  user layer: $USER ($(wc -c < "$USER") bytes)"
echo "  base layer: $BASE ($(wc -c < "$BASE") bytes)"
