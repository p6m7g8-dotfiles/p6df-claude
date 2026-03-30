#!/usr/bin/env bash
# Layer N — Chain watchdog: watches supervisor.py itself.
# Runs via cron every 5 minutes as the watchdog-of-the-watchdog.
# Uses flock to prevent split-brain with supervisor.py.

set -euo pipefail

LOCK="/tmp/p6df-claude-chain-watchdog.lock"
exec 9>"$LOCK"
flock -n 9 || exit 0

SUPERVISOR_DIR="${HOME}/.claude/supervisor"
LOG="${SUPERVISOR_DIR}/interventions.log"

log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  echo "{\"ts\":\"${ts}\",\"event\":\"$1\",\"layer\":\"N-chain-watchdog\",\"detail\":\"$2\"}" >> "$LOG" 2>/dev/null || true
}

is_running_not_zombie() {
  local name="$1"
  local pid
  pid=$(pgrep -f "$name" 2>/dev/null | head -1)
  [ -z "$pid" ] && return 1
  local stat
  stat=$(ps -p "$pid" -o stat= 2>/dev/null || echo "Z")
  [[ "$stat" != *Z* ]]
}

if ! is_running_not_zombie "supervisor.py"; then
  nohup python3 "${SUPERVISOR_DIR}/supervisor.py" \
    >> "${SUPERVISOR_DIR}/supervisor.log" 2>&1 &
  log "supervisor_restarted" "chain-watchdog"
fi
