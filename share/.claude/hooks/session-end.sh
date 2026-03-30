#!/usr/bin/env bash
# Cross-cutting #12 — SessionEnd hook: cleanup on session end.
#
# Fires when a session terminates. Cannot block.
# 1. Removes session from swarm registry
# 2. Deletes heartbeat entry
# 3. Releases any held swarm locks
# 4. Writes final state to task-state.jsonl

set -euo pipefail

SUPERVISOR_DIR="${HOME}/.claude/supervisor"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  echo "{\"ts\":\"${ts}\",\"event\":\"$1\",\"layer\":\"session-end\",\"detail\":\"$2\"}" \
    >> "${SUPERVISOR_DIR}/interventions.log" 2>/dev/null || true
}

# Remove from registry
python3 - << 'PYEOF' 2>/dev/null || true
import json, os, fcntl
session_id = os.environ.get("CLAUDE_SESSION_ID", "unknown")
reg = os.path.expanduser("~/.claude/supervisor/swarm-registry.json")
lock = os.path.expanduser("~/.claude/supervisor/.registry.lock")
try:
    with open(lock, "w") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            with open(reg) as f: registry = json.load(f)
            registry.get("swarms", {}).pop(session_id, None)
            tmp = reg + ".tmp"
            with open(tmp, "w") as f: json.dump(registry, f, indent=2)
            os.replace(tmp, reg)
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)
except: pass
PYEOF

# Remove heartbeat
rm -f "${SUPERVISOR_DIR}/heartbeats/${SESSION_ID}" 2>/dev/null || true

# Release any locks held by this session
python3 - << 'PYEOF' 2>/dev/null || true
import json, os, fcntl
session_id = os.environ.get("CLAUDE_SESSION_ID", "unknown")
locks_path = os.path.expanduser("~/.claude/supervisor/swarm-locks.json")
lock_file = os.path.expanduser("~/.claude/supervisor/.locks.lock")
try:
    with open(lock_file, "w") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            with open(locks_path) as f: locks = json.load(f)
            locks = {k: v for k, v in locks.items() if v.get("agent_id") != session_id}
            tmp = locks_path + ".tmp"
            with open(tmp, "w") as f: json.dump(locks, f)
            os.replace(tmp, locks_path)
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)
except: pass
PYEOF

log "session_ended" "${SESSION_ID}"
exit 0
