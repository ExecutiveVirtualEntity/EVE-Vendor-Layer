#!/usr/bin/env bash
# install.sh — Bootstrap a fresh Ubuntu 24.04 box to E.V.E. vendor-layer parity.
#
# Run as the `eve` user (not root) on a clean box. Idempotent — safe to re-run.
# Customer-layer configuration (OAuth, WhatsApp pairing, vault content, instance
# persona) is handled separately by the dashboard (Phase 2.5).
#
# Usage:
#   git clone git@github.com:ExecutiveVirtualEntity/EVE-Vendor-Layer.git ~/eve-vendor-layer
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

# ─── Phase L1 — registration token + quick tunnel ────────────────────────────
# Generates the bearer secret the box uses against the dashboard's
# /api/box/sync, and starts a Cloudflare quick tunnel pointing at the
# WhatsApp bridge port (8080). The tunnel URL + token are what the
# operator pastes into /admin → Register Box.
phase_register() {
  phase "Phase L1 — registration token + cloudflare quick tunnel"

  local config_dir="${EVE_HOME}/.config/eve"
  local token_file="${config_dir}/registration.token"
  local tunnel_file="${config_dir}/tunnel.url"

  mkdir -p "${config_dir}"
  chmod 700 "${config_dir}"

  if [[ -f "${token_file}" ]]; then
    ok "registration token already exists at ${token_file} (re-using)"
  else
    info "Generating 32-byte registration token..."
    head -c 32 /dev/urandom | xxd -p -c 64 > "${token_file}"
    chmod 600 "${token_file}"
    ok "registration token written to ${token_file}"
  fi

  # Cloudflare "quick tunnel" — no account required, gives an ephemeral
  # https://*.trycloudflare.com URL pointed at localhost:8080. PM2 will
  # supervise the tunnel daemon so it restarts on reboot, but the URL
  # changes whenever cloudflared restarts (quick-tunnel limitation). For
  # a stable URL the customer can graduate to a named tunnel later.
  if pm2 describe cloudflared-quick >/dev/null 2>&1; then
    ok "cloudflared-quick tunnel already supervised by PM2"
  else
    info "Starting cloudflared quick tunnel under PM2..."
    pm2 start --name cloudflared-quick --silent \
      cloudflared -- tunnel --url http://localhost:8080 || \
      warn "pm2 start cloudflared-quick failed (run manually if needed)"
    pm2 save --force >/dev/null 2>&1 || true
  fi

  info "Waiting up to 30s for cloudflared to emit a tunnel URL..."
  local found_url=""
  for _ in $(seq 1 30); do
    sleep 1
    # Quick tunnels print "Your quick Tunnel has been created! Visit it at:"
    # followed by the URL. We grep PM2's stdout/err log for it.
    found_url=$(pm2 logs cloudflared-quick --nostream --lines 200 2>/dev/null | \
      grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -n 1)
    if [[ -n "${found_url}" ]]; then break; fi
  done

  if [[ -n "${found_url}" ]]; then
    echo "${found_url}" > "${tunnel_file}"
    chmod 600 "${tunnel_file}"
    ok "tunnel URL captured: ${found_url}"
  else
    warn "couldn't capture a tunnel URL from cloudflared logs in 30s"
    warn "run 'pm2 logs cloudflared-quick' and copy the trycloudflare URL manually"
  fi
}

# ─── Phase M — final notes ───────────────────────────────────────────────────
phase_final() {
  phase "Phase M — vendor parity reached; next steps for the operator"

  local token_file="${EVE_HOME}/.config/eve/registration.token"
  local tunnel_file="${EVE_HOME}/.config/eve/tunnel.url"

  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo " REGISTER THIS BOX IN THE DASHBOARD"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  if [[ -f "${token_file}" ]]; then
    echo "  Registration token: $(cat "${token_file}")"
  else
    echo "  Registration token: (missing — Phase L1 failed)"
  fi
  if [[ -f "${tunnel_file}" ]]; then
    echo "  Tunnel URL:         $(cat "${tunnel_file}")"
  else
    echo "  Tunnel URL:         (not captured — check pm2 logs cloudflared-quick)"
  fi
  echo ""
  echo "  → Paste both into https://dashboard.executivevirtualentity.com/admin"
  echo "    (Boxes section → + Register box)"
  echo ""
  echo "  Once a customer is assigned to this box on /admin, eve-sync"
  echo "  (cron, runs every minute) will pull their personalization and"
  echo "  apply it to ~/.config/eve/instance.env automatically."
  echo "═══════════════════════════════════════════════════════════════════"

  cat <<EOF

Other one-time tasks the operator/customer still does:
  • Google Workspace OAuth — handled by the customer in /app
  • WhatsApp QR pairing — handled by the customer in /app
  • Tailscale auth — sudo tailscale up (for remote ops)
  • Cron entries — crontab ${REPO_DIR}/cron/eve-cron.crontab.template

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
  phase_register
  phase_final

  echo ""
  ok "Done. Log: ${LOG_FILE}"
}

main "$@"
