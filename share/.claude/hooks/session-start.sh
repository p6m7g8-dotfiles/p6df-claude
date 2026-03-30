#!/usr/bin/env bash
# Layer A + E + G + V — SessionStart hook: self-healing and session registration.
#
# Fires once when Claude Code starts. Cannot block (exit code ignored).
# 1. Repairs hook symlinks, settings.json, CLAUDE.md, rules/, agents/ (Layer E)
# 2. Writes active-session.json with tmux pane for external monitor (Layer G/V)
# 3. Verifies hook scripts compile (Layer AG)
# 4. Ensures supervisor daemons are running (Layer N)
# 5. Drains pending-inject sentinel if present (Layer M)
# 6. Writes initial task anchor (Layer AI)

set -euo pipefail

SOURCE="${HOME}/.p6/p6m7g8-dotfiles/p6df-claude/share/.claude"
CLAUDE_DIR="${HOME}/.claude"
SUPERVISOR_DIR="${HOME}/.claude/supervisor"
LOG="${SUPERVISOR_DIR}/interventions.log"
REPAIRED=()

log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  echo "{\"ts\":\"${ts}\",\"event\":\"$1\",\"layer\":\"A-session-start\",\"detail\":\"$2\"}" >> "$LOG" 2>/dev/null || true
}

# ── 1. Self-heal symlinks ────────────────────────────────────────────────────
ensure_symlink() {
  local target="$1" link="$2" label="$3"
  [ -e "$target" ] || return 0
  local needs_repair=0
  if [ ! -e "$link" ]; then
    needs_repair=1
  elif [ -L "$link" ]; then
    current="$(readlink "$link" 2>/dev/null || echo "")"
    [ "$current" != "$target" ] && needs_repair=1
  fi
  if [ "$needs_repair" -eq 1 ]; then
    rm -rf "$link"
    ln -sf "$target" "$link"
    REPAIRED+=("$label")
    log "symlink_repaired" "$label"
  fi
}

ensure_symlink "${SOURCE}/hooks"       "${CLAUDE_DIR}/hooks"       "hooks/"
ensure_symlink "${SOURCE}/rules"       "${CLAUDE_DIR}/rules"       "rules/"
ensure_symlink "${SOURCE}/agents"      "${CLAUDE_DIR}/agents"      "agents/"
ensure_symlink "${SOURCE}/CLAUDE.md"   "${CLAUDE_DIR}/CLAUDE.md"   "CLAUDE.md"

# settings.json: only repair if missing or broken symlink (not a real file with hooks)
if [ ! -e "${CLAUDE_DIR}/settings.json" ]; then
  ln -sf "${SOURCE}/settings.json" "${CLAUDE_DIR}/settings.json"
  REPAIRED+=("settings.json")
  log "symlink_repaired" "settings.json"
elif [ -L "${CLAUDE_DIR}/settings.json" ]; then
  current="$(readlink "${CLAUDE_DIR}/settings.json" 2>/dev/null || echo "")"
  if [ "$current" != "${SOURCE}/settings.json" ]; then
    rm -f "${CLAUDE_DIR}/settings.json"
    ln -sf "${SOURCE}/settings.json" "${CLAUDE_DIR}/settings.json"
    REPAIRED+=("settings.json")
    log "symlink_repaired" "settings.json"
  fi
fi

# ── 2. Write active-session.json ─────────────────────────────────────────────
mkdir -p "${SUPERVISOR_DIR}"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TMUX_PANE_VAL="${TMUX_PANE:-}"
TRANSCRIPT="${CLAUDE_TRANSCRIPT_PATH:-}"
cat > "${SUPERVISOR_DIR}/active-session.json.tmp" << EOF
{
  "session_id": "${SESSION_ID}",
  "tmux_pane": "${TMUX_PANE_VAL}",
  "transcript_path": "${TRANSCRIPT}",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")",
  "tmux_session": "${TMUX:-}"
}
EOF
mv "${SUPERVISOR_DIR}/active-session.json.tmp" "${SUPERVISOR_DIR}/active-session.json"
log "session_registered" "${SESSION_ID}"

# ── 3. Register in swarm registry ────────────────────────────────────────────
python3 - << 'PYEOF' 2>/dev/null || true
import json, os, time, fcntl
reg = os.path.expanduser("~/.claude/supervisor/swarm-registry.json")
lock = os.path.expanduser("~/.claude/supervisor/.registry.lock")
session_id = os.environ.get("CLAUDE_SESSION_ID", "unknown")
tmux_pane = os.environ.get("TMUX_PANE", "")
transcript = os.environ.get("CLAUDE_TRANSCRIPT_PATH", "")
os.makedirs(os.path.dirname(reg), exist_ok=True)
try:
    with open(lock, "w") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            registry = {}
            try:
                with open(reg) as f: registry = json.load(f)
            except: pass
            swarms = registry.setdefault("swarms", {})
            swarms[session_id] = {
                "root": {"session_id": session_id, "tmux_pane": tmux_pane,
                         "transcript_path": transcript, "started_at": time.time(),
                         "last_heartbeat": time.time(), "status": "active"},
                "agents": {}
            }
            tmp = reg + ".tmp"
            with open(tmp, "w") as f: json.dump(registry, f, indent=2)
            os.replace(tmp, reg)
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)
except: pass
PYEOF

# ── 4. Verify hook scripts compile ───────────────────────────────────────────
HOOKS_DIR="${CLAUDE_DIR}/hooks"
if [ -d "$HOOKS_DIR" ]; then
  for py in "${HOOKS_DIR}"/*.py; do
    [ -f "$py" ] || continue
    if ! python3 -m py_compile "$py" 2>/dev/null; then
      log "hook_compile_error" "$py"
      echo "[session-start] WARNING: Hook compile error: $py" >&2
    fi
  done
fi

# ── 5. Ensure supervisor daemons running ─────────────────────────────────────
for daemon in monitor swarm-monitor supervisor credential-monitor billing-governor message-bus; do
  if ! pgrep -f "${daemon}.py" > /dev/null 2>&1; then
    script="${SUPERVISOR_DIR}/${daemon}.py"
    [ -f "$script" ] || continue
    nohup python3 "$script" >> "${SUPERVISOR_DIR}/${daemon}.log" 2>&1 &
    log "daemon_started" "$daemon"
  fi
done

# ── 6. Handle pending-inject sentinel ────────────────────────────────────────
PENDING="${SUPERVISOR_DIR}/pending-inject"
if [ -f "$PENDING" ]; then
  INJECT_MSG=$(cat "$PENDING" 2>/dev/null || echo "")
  rm -f "$PENDING"
  log "pending_inject_found" "${INJECT_MSG:0:80}"
  # Message will be picked up by UserPromptSubmit queue on first turn
  mkdir -p "${SUPERVISOR_DIR}/messages"
  echo "{\"ts\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"from_agent\":\"session-start\",\"message\":\"${INJECT_MSG}\"}" \
    >> "${SUPERVISOR_DIR}/messages/${SESSION_ID}.queue" 2>/dev/null || true
fi

[ ${#REPAIRED[@]} -gt 0 ] && echo "[session-start] Repaired: ${REPAIRED[*]}"
exit 0
