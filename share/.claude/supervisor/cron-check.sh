#!/usr/bin/env bash
# Layer D — Cron backup: runs every minute via crontab.
# Checks that supervisor daemons are running; restarts if not.
# Independent of launchd — survives launchd failure.

set -euo pipefail

# Prevent overlapping runs
LOCK="/tmp/p6df-claude-cron.lock"
exec 9>"$LOCK"
flock -n 9 || exit 0

SUPERVISOR_DIR="${HOME}/.claude/supervisor"
LOG="${SUPERVISOR_DIR}/interventions.log"

# Source credentials (cron has no shell env)
source "${SUPERVISOR_DIR}/env-heal.sh" 2>/dev/null || true

log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  echo "{\"ts\":\"${ts}\",\"event\":\"$1\",\"layer\":\"D-cron\",\"detail\":\"$2\"}" >> "$LOG" 2>/dev/null || true
}

start_if_dead() {
  local script_name="$1"
  local script_path="${SUPERVISOR_DIR}/${script_name}"
  [ -f "$script_path" ] || return 0

  if ! pgrep -f "$script_name" > /dev/null 2>&1; then
    nohup python3 "$script_path" >> "${SUPERVISOR_DIR}/${script_name%.py}.log" 2>&1 &
    log "cron_restarted" "$script_name"
  fi
}

start_if_dead "supervisor.py"
start_if_dead "monitor.py"
start_if_dead "swarm-monitor.py"
start_if_dead "credential-monitor.py"
start_if_dead "billing-governor.py"
start_if_dead "message-bus.py"

# Re-verify launchd plists are loaded (macOS)
if command -v launchctl &>/dev/null; then
  for label in com.p6df.claude-monitor com.p6df.claude-supervisor; do
    if ! launchctl list "$label" &>/dev/null; then
      plist="${HOME}/Library/LaunchAgents/${label}.plist"
      [ -f "$plist" ] && launchctl load "$plist" 2>/dev/null && log "plist_reloaded" "$label" || true
    fi
  done
fi
