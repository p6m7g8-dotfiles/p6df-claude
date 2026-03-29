#!/usr/bin/env bash
# Master bootstrap installer for the Claude resilience system.
# Idempotent — safe to run multiple times.
#
# What it does:
#   1. Verifies prerequisites (python3, tmux, git)
#   2. Makes all scripts executable
#   3. Installs symlinks via reinstall-symlinks.sh
#   4. Generates and loads launchd plists (macOS)
#   5. Adds cron entries (D, N)
#   6. Writes managed CLAUDE.md to system path (F1) if sudo available
#   7. Writes managed settings if sudo available (O)
#   8. Stores API key in Keychain (J) if provided
#   9. Runs version guard and hook validation (AG)
#  10. Starts all supervisor daemons

set -euo pipefail

REPO="${HOME}/.p6/p6m7g8-dotfiles/p6df-claude"
SOURCE="${REPO}/share/.claude"
SUPERVISOR_DIR="${HOME}/.claude/supervisor"
LAUNCHD_DIR="${HOME}/Library/LaunchAgents"
LOG="${SUPERVISOR_DIR}/interventions.log"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[install]${NC} $*"; }
warn() { echo -e "${YELLOW}[install]${NC} $*"; }
err()  { echo -e "${RED}[install]${NC} $*" >&2; }

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
log "Checking prerequisites..."
if ! command -v python3 &>/dev/null; then
  err "python3 not found. Install Xcode CLI tools: xcode-select --install"
  exit 1
fi
python_ver=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
if python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)"; then
  log "python3 ${python_ver} ✓"
else
  err "python3 >= 3.8 required (found ${python_ver})"
  exit 1
fi

if ! command -v tmux &>/dev/null; then
  warn "tmux not found. External monitoring requires tmux. Install: brew install tmux"
fi

if ! command -v git &>/dev/null; then
  warn "git not found. Config recovery (Layer R) will be disabled."
fi

if ! command -v fswatch &>/dev/null; then
  warn "fswatch not found. Installing via brew..."
  brew install fswatch 2>/dev/null || warn "fswatch install failed — monitor will use polling"
fi

# ── 2. Make scripts executable ───────────────────────────────────────────────
log "Setting permissions..."
find "${SOURCE}/hooks" -name "*.py" -o -name "*.sh" | xargs chmod +x 2>/dev/null || true
find "${SOURCE}/supervisor" -name "*.py" -o -name "*.sh" | xargs chmod +x 2>/dev/null || true

# ── 3. Symlinks ───────────────────────────────────────────────────────────────
log "Installing symlinks..."
mkdir -p "${HOME}/.claude"
bash "${SUPERVISOR_DIR}/reinstall-symlinks.sh" 2>/dev/null || \
  bash "${SOURCE}/supervisor/reinstall-symlinks.sh"

# ── 4. launchd plists (macOS) ────────────────────────────────────────────────
if [[ "$(uname -s)" == "Darwin" ]]; then
  log "Installing launchd plists..."
  mkdir -p "$LAUNCHD_DIR"
  for tmpl in "${SOURCE}/supervisor/"*.plist.tmpl; do
    [ -f "$tmpl" ] || continue
    label=$(basename "$tmpl" .plist.tmpl)
    plist="${LAUNCHD_DIR}/${label}.plist"
    sed "s|__HOME__|${HOME}|g" "$tmpl" > "$plist"
    # Unload first to avoid "already loaded" error
    launchctl unload "$plist" 2>/dev/null || true
    launchctl load "$plist" 2>/dev/null && log "Loaded plist: $label" || warn "Could not load plist: $label"
  done
fi

# ── 5. Cron entries ───────────────────────────────────────────────────────────
log "Installing cron entries..."
CRON_SCRIPT="${SUPERVISOR_DIR}/cron-check.sh"
CHAIN_SCRIPT="${SUPERVISOR_DIR}/chain-watchdog.sh"

if command -v crontab &>/dev/null; then
  current_cron=$(crontab -l 2>/dev/null || echo "")
  new_cron="$current_cron"

  if ! echo "$current_cron" | grep -q "cron-check.sh"; then
    new_cron="${new_cron}"$'\n'"* * * * * bash ${CRON_SCRIPT} 2>/dev/null"
    log "Added cron: cron-check.sh (every minute)"
  fi
  if ! echo "$current_cron" | grep -q "chain-watchdog.sh"; then
    new_cron="${new_cron}"$'\n'"*/5 * * * * bash ${CHAIN_SCRIPT} 2>/dev/null"
    log "Added cron: chain-watchdog.sh (every 5 minutes)"
  fi
  if ! echo "$current_cron" | grep -q "config-recovery.sh"; then
    new_cron="${new_cron}"$'\n'"*/10 * * * * bash ${SUPERVISOR_DIR}/config-recovery.sh 2>/dev/null"
    log "Added cron: config-recovery.sh (every 10 minutes)"
  fi
  if ! echo "$current_cron" | grep -q "version-guard.sh"; then
    new_cron="${new_cron}"$'\n'"0 8 * * * bash ${SUPERVISOR_DIR}/version-guard.sh 2>/dev/null"
    log "Added cron: version-guard.sh (daily at 08:00)"
  fi

  if [ "$new_cron" != "$current_cron" ]; then
    echo "$new_cron" | crontab -
  fi
else
  warn "crontab not available — cron backup layer (D) disabled"
fi

# ── 6. Managed CLAUDE.md (F1) — requires sudo ────────────────────────────────
MANAGED_MD="${SOURCE}/supervisor/managed-claude-md.md"
if [[ "$(uname -s)" == "Darwin" ]]; then
  MANAGED_PATH="/Library/Application Support/ClaudeCode/CLAUDE.md"
else
  MANAGED_PATH="/etc/claude-code/CLAUDE.md"
fi

if [ -f "$MANAGED_MD" ]; then
  if sudo -n true 2>/dev/null; then
    sudo mkdir -p "$(dirname "$MANAGED_PATH")"
    sudo cp "$MANAGED_MD" "$MANAGED_PATH"
    log "Installed managed CLAUDE.md → $MANAGED_PATH"
  else
    warn "Sudo required for managed CLAUDE.md (Layer F1). Run: sudo bash $0"
  fi
fi

# ── 7. API key → Keychain (J) ────────────────────────────────────────────────
if [[ "$(uname -s)" == "Darwin" ]] && command -v security &>/dev/null; then
  if ! security find-generic-password -a claude -s anthropic -w &>/dev/null; then
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
      security add-generic-password -a claude -s anthropic -w "${ANTHROPIC_API_KEY}" 2>/dev/null && \
        log "API key stored in macOS Keychain" || warn "Could not store key in Keychain"
    else
      warn "ANTHROPIC_API_KEY not set — Keychain storage skipped (Layer J)"
    fi
  else
    log "API key already in Keychain ✓"
  fi
fi

# ── 8. Hook validation (AG) ───────────────────────────────────────────────────
log "Validating hooks..."
ERRORS=0
for py in "${HOME}/.claude/hooks/"*.py; do
  [ -f "$py" ] || continue
  if ! python3 -m py_compile "$py" 2>/dev/null; then
    err "Compile error: $py"
    ERRORS=$((ERRORS + 1))
  fi
done
[ "$ERRORS" -eq 0 ] && log "All hooks compile OK ✓" || err "${ERRORS} hook compile error(s)"

# ── 9. Start supervisor daemons ───────────────────────────────────────────────
log "Starting supervisor daemons..."
for script in monitor swarm-monitor supervisor credential-monitor billing-governor message-bus; do
  script_path="${SUPERVISOR_DIR}/${script}.py"
  [ -f "$script_path" ] || continue
  if ! pgrep -f "${script}.py" > /dev/null 2>&1; then
    nohup python3 "$script_path" >> "${SUPERVISOR_DIR}/${script}.log" 2>&1 &
    log "Started: ${script}"
  else
    log "Already running: ${script} ✓"
  fi
done

log ""
log "Installation complete! Claude resilience system is active."
log "Logs: ${SUPERVISOR_DIR}/*.log"
log "Audit: ${LOG}"
