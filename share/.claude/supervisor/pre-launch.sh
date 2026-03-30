#!/usr/bin/env bash
# Layer G — Pre-launch: runs before every `claude` invocation via shell wrapper.
# 1. Writes active-session.json with current tmux pane (for monitor)
# 2. Ensures supervisor daemons are running
# 3. Validates settings.json exists and parses

SUPERVISOR_DIR="${HOME}/.claude/supervisor"
mkdir -p "${SUPERVISOR_DIR}"

# Write session info (session_id not yet known pre-launch, updated by SessionStart hook)
cat > "${SUPERVISOR_DIR}/active-session.json.tmp" << EOF
{
  "session_id": "pre-launch",
  "tmux_pane": "${TMUX_PANE:-}",
  "tmux_session": "${TMUX:-}",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")",
  "transcript_path": ""
}
EOF
mv "${SUPERVISOR_DIR}/active-session.json.tmp" "${SUPERVISOR_DIR}/active-session.json"

# Ensure monitor is running
if ! pgrep -f 'monitor.py' > /dev/null 2>&1; then
  if [ -f "${SUPERVISOR_DIR}/monitor.py" ]; then
    nohup python3 "${SUPERVISOR_DIR}/monitor.py" \
      >> "${SUPERVISOR_DIR}/monitor.log" 2>&1 &
  fi
fi

# Validate settings.json
if [ -f "${HOME}/.claude/settings.json" ]; then
  if ! python3 -m json.tool "${HOME}/.claude/settings.json" > /dev/null 2>&1; then
    echo "[pre-launch] WARNING: settings.json is invalid — repairing" >&2
    bash "${SUPERVISOR_DIR}/reinstall-symlinks.sh" 2>/dev/null || true
  fi
fi

# Warn if not in tmux
if [ -z "${TMUX:-}" ]; then
  echo "[pre-launch] WARNING: Not in a tmux session. External monitoring requires tmux." >&2
fi
