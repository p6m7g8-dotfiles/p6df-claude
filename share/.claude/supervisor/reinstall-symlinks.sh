#!/usr/bin/env bash
# Layer E standalone — reinstall all Claude resilience symlinks.
# Safe to run multiple times (idempotent). Called by session-start.sh,
# config-recovery.sh, and install.sh.

set -euo pipefail

SOURCE="${HOME}/.p6/p6m7g8-dotfiles/p6df-claude/share/.claude"
CLAUDE_DIR="${HOME}/.claude"
LOG="${HOME}/.claude/supervisor/interventions.log"

log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  echo "{\"ts\":\"${ts}\",\"event\":\"symlink_$1\",\"layer\":\"E-symlinks\",\"detail\":\"$2\"}" >> "$LOG" 2>/dev/null || true
}

ensure_symlink() {
  local target="$1" link="$2" label="$3"
  [ -e "$target" ] || { echo "[symlinks] Source missing: $target"; return 0; }

  # If real file (not symlink) and it has content, back it up
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    if [ -s "$link" ]; then
      cp -a "$link" "${link}.bak.$(date +%s)"
    fi
    rm -rf "$link"
  fi

  local needs_repair=0
  if [ ! -e "$link" ]; then
    needs_repair=1
  elif [ -L "$link" ] && [ "$(readlink "$link")" != "$target" ]; then
    needs_repair=1
  fi

  if [ "$needs_repair" -eq 1 ]; then
    rm -rf "$link"
    ln -sf "$target" "$link"
    log "repaired" "$label"
    echo "[symlinks] Repaired: $label"
  fi
}

ensure_symlink "${SOURCE}/hooks"       "${CLAUDE_DIR}/hooks"       "hooks/"
ensure_symlink "${SOURCE}/rules"       "${CLAUDE_DIR}/rules"       "rules/"
ensure_symlink "${SOURCE}/agents"      "${CLAUDE_DIR}/agents"      "agents/"
ensure_symlink "${SOURCE}/supervisor"  "${CLAUDE_DIR}/supervisor"  "supervisor/"
ensure_symlink "${SOURCE}/CLAUDE.md"   "${CLAUDE_DIR}/CLAUDE.md"   "CLAUDE.md"
ensure_symlink "${SOURCE}/settings.json" "${CLAUDE_DIR}/settings.json" "settings.json"
