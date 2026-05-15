#!/usr/bin/env bash
# install.sh — Bootstrap a fresh Ubuntu 24.04 box to E.V.E. vendor-layer parity.
#
# Run as the `eve` user (not root) on a clean box. Idempotent — safe to re-run.
# Customer-layer configuration (OAuth, WhatsApp pairing, vault content, instance
# persona) is handled separately by the dashboard (Phase 2.5).
#
# Usage:
#   git clone git@github.com:EvolvingVirtualEntity/EVE-Vendor-Layer.git ~/eve-vendor-layer
#   cd ~/eve-vendor-layer
#   ./install.sh

set -euo pipefail

# ─── Paths ──────────────────────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVE_HOME="${HOME}"
EVE_TOOLS="${EVE_HOME}/.local/eve-tools"
VAULT="${EVE_HOME}/EveBrain"
MEMORY_DIR="${EVE_HOME}/.claude/projects/-home-eve-EveBrain/memory"
LOG_FILE="${EVE_HOME}/install-eve-$(date +%Y%m%d-%H%M%S).log"

# ─── Logging helpers ─────────────────────────────────────────────────────────
exec > >(tee -a "${LOG_FILE}") 2>&1

info()  { echo -e "\033[34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[32m[ OK ]\033[0m  $*"; }
warn()  { echo -e "\033[33m[WARN]\033[0m  $*"; }
fail()  { echo -e "\033[31m[FAIL]\033[0m  $*" >&2; exit 1; }
phase() { echo ""; echo -e "\033[1;36m=== $* ===\033[0m"; }

# ─── Phase A — sanity checks ─────────────────────────────────────────────────
phase_sanity() {
  phase "Phase A — sanity checks"

  # Ubuntu version
  if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    fail "This installer targets Ubuntu. Detected: $(cat /etc/os-release | grep PRETTY_NAME)"
  fi
  if ! grep -q "VERSION_ID=\"24.04\"" /etc/os-release; then
    warn "Targets Ubuntu 24.04; detected $(grep VERSION_ID /etc/os-release). Proceeding but watch for breakage."
  fi

  # Not root
  if [[ $EUID -eq 0 ]]; then
    fail "Run as a non-root user (recommended username: 'eve'). Aborting."
  fi

  # Has sudo
  if ! sudo -n true 2>/dev/null; then
    info "This installer needs sudo for apt + service installs. You may be prompted."
    sudo -v || fail "sudo unavailable. Aborting."
  fi

  # Internet
  if ! curl -fsS -o /dev/null --max-time 5 https://github.com; then
    fail "No internet (github.com unreachable). Aborting."
  fi

  ok "User: $(whoami), Home: ${HOME}, Repo: ${REPO_DIR}, Log: ${LOG_FILE}"
}

# ─── Phase B — apt + external repos ──────────────────────────────────────────
phase_apt() {
  phase "Phase B — apt repos + packages"

  # NodeSource (Node 20 LTS)
  if [[ ! -f /etc/apt/sources.list.d/nodesource.sources ]]; then
    info "Adding NodeSource repo (Node 20 LTS)..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  else
    ok "NodeSource repo already present"
  fi

  # Cloudflare (cloudflared)
  if [[ ! -f /etc/apt/sources.list.d/cloudflared.list ]]; then
    info "Adding Cloudflare repo..."
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
  else
    ok "Cloudflare repo already present"
  fi

  # Tailscale
  if [[ ! -f /etc/apt/sources.list.d/tailscale.list ]]; then
    info "Adding Tailscale repo..."
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
  else
    ok "Tailscale repo already present"
  fi

  info "Running apt-get update..."
  sudo apt-get update -qq

  info "Installing system packages from manifest/apt-packages.txt..."
  local pkgs
  pkgs=$(grep -v '^#' "${REPO_DIR}/manifest/apt-packages.txt" | grep -v '^$' | tr '\n' ' ')
  # shellcheck disable=SC2086
  sudo apt-get install -y -qq ${pkgs} nodejs cloudflared tailscale

  ok "apt packages installed"
}

# ─── Phase C — npm global packages ───────────────────────────────────────────
phase_npm() {
  phase "Phase C — npm global packages"

  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    info "Installing global: $line"
    sudo npm install -g "$line"
  done < "${REPO_DIR}/manifest/npm-global.txt"

  ok "npm global packages installed"
}

# ─── Phase D — uv (Astral, Python venv manager) ──────────────────────────────
phase_uv() {
  phase "Phase D — uv (Python venv manager)"

  if command -v uv >/dev/null; then
    ok "uv already installed: $(uv --version)"
    return
  fi
  info "Installing uv via Astral installer..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # Pick up uv in this shell session
  export PATH="${HOME}/.local/bin:${PATH}"
  ok "uv installed: $(uv --version)"
}

# ─── Phase E — Python venvs ──────────────────────────────────────────────────
phase_venvs() {
  phase "Phase E — Python venvs"

  mkdir -p "${EVE_TOOLS}"

  for req in "${REPO_DIR}/manifest/venv-requirements"/*.txt; do
    local name
    name=$(basename "${req}" .txt)

    # whatsapp-mcp-server lives under ~/whatsapp-mcp/, others under ~/.local/eve-tools/
    local venv_dir
    if [[ "${name}" == "whatsapp-mcp-server" ]]; then
      venv_dir="${EVE_HOME}/whatsapp-mcp/whatsapp-mcp-server/.venv"
      mkdir -p "$(dirname "${venv_dir}")"
    else
      venv_dir="${EVE_TOOLS}/${name}"
    fi

    if [[ -d "${venv_dir}" ]]; then
      ok "venv ${name} already exists at ${venv_dir}"
    else
      info "Creating venv ${name} at ${venv_dir}..."
      uv venv "${venv_dir}"
    fi

    info "Installing ${name} deps ($(wc -l < "${req}") packages)..."
    uv pip install --python "${venv_dir}/bin/python" -r "${req}" --quiet
    ok "venv ${name} ready"
  done
}

# ─── Phase F — Ollama ────────────────────────────────────────────────────────
phase_ollama() {
  phase "Phase F — Ollama"

  if ! command -v ollama >/dev/null; then
    info "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
  else
    ok "Ollama already installed: $(ollama --version)"
  fi

  # Pull models
  while IFS= read -r model; do
    [[ -z "$model" || "$model" =~ ^# ]] && continue
    if ollama list | grep -q "${model%%:*}"; then
      ok "model already present: ${model}"
    else
      info "Pulling model: ${model}"
      ollama pull "${model}"
    fi
  done < "${REPO_DIR}/manifest/ollama-models.txt"
}

# ─── Phase G — Piper voices ──────────────────────────────────────────────────
phase_piper() {
  phase "Phase G — Piper voices"

  local voices_dir="${EVE_TOOLS}/piper-voices"
  mkdir -p "${voices_dir}"

  while IFS= read -r voice; do
    [[ -z "$voice" || "$voice" =~ ^# ]] && continue
    local onnx="${voices_dir}/${voice}.onnx"
    if [[ -f "${onnx}" ]]; then
      ok "voice already present: ${voice}"
      continue
    fi

    # Parse e.g. "en_US-amy-medium" → lang=en_US, name=amy, quality=medium
    local lang name quality
    lang=$(echo "${voice}" | cut -d- -f1)
    name=$(echo "${voice}" | cut -d- -f2)
    quality=$(echo "${voice}" | cut -d- -f3)
    local base_url="https://huggingface.co/rhasspy/piper-voices/resolve/main/${lang%_*}/${lang}/${name}/${quality}"

    info "Downloading ${voice} from huggingface..."
    curl -fsSL -o "${onnx}" "${base_url}/${voice}.onnx" || warn "failed to fetch ${voice}.onnx"
    curl -fsSL -o "${onnx}.json" "${base_url}/${voice}.onnx.json" || warn "failed to fetch ${voice}.onnx.json"
    ok "voice installed: ${voice}"
  done < "${REPO_DIR}/manifest/piper-voices.txt"
}

# ─── Phase H — eve-tools deployment ──────────────────────────────────────────
phase_eve_tools() {
  phase "Phase H — eve-tools deployment"

  mkdir -p "${EVE_TOOLS}"

  info "Copying eve-tools/ → ${EVE_TOOLS}/"
  cp -r "${REPO_DIR}/eve-tools/"* "${EVE_TOOLS}/"

  # The assembler also lives in ~/.local/eve-tools/ per the Phase 1 convention
  cp "${REPO_DIR}/assemble-claude.sh" "${EVE_TOOLS}/"

  # Make sure scripts are executable
  chmod +x "${EVE_TOOLS}"/*.py "${EVE_TOOLS}"/*.sh 2>/dev/null || true

  ok "eve-tools deployed"
}

# ─── Phase I — sharedbrain deployment ────────────────────────────────────────
phase_sharedbrain() {
  phase "Phase I — sharedbrain (Node web server)"

  local sb_dir="${EVE_HOME}/sharedbrain"
  mkdir -p "${sb_dir}"
  info "Copying bridges/sharedbrain/ → ${sb_dir}/"
  cp -r "${REPO_DIR}/bridges/sharedbrain/"* "${sb_dir}/"

  info "Running npm install..."
  (cd "${sb_dir}" && npm install --silent)

  ok "sharedbrain deployed"
}

# ─── Phase J — whatsapp-mcp deployment ───────────────────────────────────────
phase_whatsapp_mcp() {
  phase "Phase J — whatsapp-mcp (Go bridge + Python MCP)"

  local wm_dir="${EVE_HOME}/whatsapp-mcp"
  mkdir -p "${wm_dir}/whatsapp-bridge" "${wm_dir}/whatsapp-mcp-server"

  info "Copying bridge source..."
  cp -r "${REPO_DIR}/bridges/whatsapp-mcp/whatsapp-bridge/"* "${wm_dir}/whatsapp-bridge/"
  cp -r "${REPO_DIR}/bridges/whatsapp-mcp/whatsapp-mcp-server/"* "${wm_dir}/whatsapp-mcp-server/"
  cp "${REPO_DIR}/bridges/whatsapp-mcp/LICENSE" "${wm_dir}/" 2>/dev/null || true
  cp "${REPO_DIR}/bridges/whatsapp-mcp/README.md" "${wm_dir}/" 2>/dev/null || true

  info "Building Go bridge..."
  (cd "${wm_dir}/whatsapp-bridge" && go build -o whatsapp-bridge .)

  # MCP server venv already created in Phase E if requirements file is present.
  ok "whatsapp-mcp deployed; binary at ${wm_dir}/whatsapp-bridge/whatsapp-bridge"
}

# ─── Phase K — Vault + memory skeleton ───────────────────────────────────────
phase_skeleton() {
  phase "Phase K — vault + memory skeleton"

  # Vault dirs
  for d in 00-Inbox 01-Daily 02-Projects 03-People 04-Resources 05-Archive; do
    mkdir -p "${VAULT}/${d}"
  done
  ok "vault skeleton ready at ${VAULT}/"

  # Drop CLAUDE.base.md
  cp "${REPO_DIR}/CLAUDE.base.md" "${VAULT}/"
  ok "CLAUDE.base.md installed"

  # Memory: vendor side (from this repo), user side (empty for customer to fill)
  mkdir -p "${MEMORY_DIR}/vendor" "${MEMORY_DIR}/user"
  cp "${REPO_DIR}/memory/vendor/"*.md "${MEMORY_DIR}/vendor/"
  ok "memory/vendor populated ($(ls "${MEMORY_DIR}/vendor" | wc -l) files)"

  # MEMORY.md starter — customer fills/extends this on first run via dashboard.
  if [[ ! -f "${MEMORY_DIR}/MEMORY.md" ]]; then
    cat > "${MEMORY_DIR}/MEMORY.md" <<'EOF'
<!-- MEMORY.md — the index of vendor + user memory files. Vendor entries are
seeded by install.sh from this repo; user entries are added as the instance
accumulates feedback. Customer dashboard helps maintain this list. -->
EOF
    ok "MEMORY.md initialized (empty index)"
  else
    ok "MEMORY.md already exists; preserving"
  fi
}

# ─── Phase L — assemble CLAUDE.md ────────────────────────────────────────────
phase_assemble() {
  phase "Phase L — assemble CLAUDE.md"

  if [[ ! -f "${VAULT}/CLAUDE.user.md" ]]; then
    warn "CLAUDE.user.md not found at ${VAULT}/. Skipping assembly — the customer dashboard creates this on first onboard."
    return
  fi
  bash "${EVE_TOOLS}/assemble-claude.sh"
  ok "CLAUDE.md assembled at ${VAULT}/"
}

# ─── Phase M — final notes ───────────────────────────────────────────────────
phase_final() {
  phase "Phase M — vendor parity reached; next steps for the operator"

  cat <<'EOF'

Vendor-layer install complete. This box is now at parity with the L&R
reference box (minus the instance-layer: persona, OAuth, WhatsApp pairing,
vault content, credentials).

To reach a fully-running instance, the customer dashboard (Phase 2.5) wires:
  1) Google Workspace OAuth → tokens land in ~/.google_workspace_mcp/credentials/
  2) WhatsApp QR pairing → whatsapp-mcp/whatsapp-bridge stores session
  3) Cloudflared tunnel auth → ~/.cloudflared/<tunnel-id>.json
  4) Tailscale auth → sudo tailscale up
  5) CLAUDE.user.md populated with team info → run assemble-claude.sh
  6) cron entries enabled (see cron/eve-cron.crontab.template once created)
  7) PM2 services started (see systemd/pm2-eve.service template once created)

Until the dashboard is built, the operator does these manually (matching how
the L&R box was originally set up). Refer to the L&R Eve box for the canonical
known-good config.

Log of this install: ${LOG_FILE}
EOF
}

# ─── main ────────────────────────────────────────────────────────────────────
main() {
  info "E.V.E. vendor-layer installer starting"
  info "Repo dir: ${REPO_DIR}"

  phase_sanity
  phase_apt
  phase_npm
  phase_uv
  phase_venvs
  phase_ollama
  phase_piper
  phase_eve_tools
  phase_sharedbrain
  phase_whatsapp_mcp
  phase_skeleton
  phase_assemble
  phase_final

  echo ""
  ok "Done. Log: ${LOG_FILE}"
}

main "$@"
