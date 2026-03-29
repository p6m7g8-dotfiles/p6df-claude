#!/usr/bin/env bash
# Layer AG — Version guard: detects Claude Code version changes and
# validates hook scripts are still functional.
# Runs at SessionStart and daily via cron.

set -euo pipefail

SUPERVISOR_DIR="${HOME}/.claude/supervisor"
VERSION_FILE="${SUPERVISOR_DIR}/last-known-version"
HOOKS_DIR="${HOME}/.claude/hooks"
LOG="${SUPERVISOR_DIR}/interventions.log"

log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  echo "{\"ts\":\"${ts}\",\"event\":\"$1\",\"layer\":\"AG-version-guard\",\"detail\":\"$2\"}" >> "$LOG" 2>/dev/null || true
}

# Get current version
current_version=$(claude --version 2>/dev/null | head -1 || echo "unknown")
last_version=$(cat "$VERSION_FILE" 2>/dev/null || echo "")

if [ "$current_version" != "$last_version" ] && [ "$current_version" != "unknown" ]; then
  log "version_changed" "from=${last_version} to=${current_version}"
  echo "[version-guard] Claude Code version changed: ${last_version} → ${current_version}" >&2

  # Validate hook scripts compile
  ERRORS=0
  if [ -d "$HOOKS_DIR" ]; then
    for py in "${HOOKS_DIR}"/*.py; do
      [ -f "$py" ] || continue
      if ! python3 -m py_compile "$py" 2>/dev/null; then
        echo "[version-guard] COMPILE ERROR: $py" >&2
        log "hook_compile_error" "$py"
        ERRORS=$((ERRORS + 1))
      fi
    done
  fi

  # Verify settings.json contains critical hooks
  if command -v python3 &>/dev/null && [ -f "${HOME}/.claude/settings.json" ]; then
    python3 - << 'PYEOF' 2>/dev/null || { log "settings_missing_hooks" ""; echo "[version-guard] WARNING: settings.json missing hook registrations" >&2; }
import json
with open(f"{__import__('os').path.expanduser('~')}/.claude/settings.json") as f:
    s = json.load(f)
required = {"Stop", "SubagentStop", "PreToolUse", "UserPromptSubmit", "SessionStart"}
missing = required - set(s.get("hooks", {}).keys())
if missing:
    raise ValueError(f"Missing hooks: {missing}")
PYEOF
  fi

  if [ "$ERRORS" -gt 0 ]; then
    bash "${SUPERVISOR_DIR}/notify.sh" "Claude Code Updated" \
      "Version ${current_version}: ${ERRORS} hook compile error(s). Check ~/.claude/supervisor/interventions.log" 2>/dev/null || true
  else
    bash "${SUPERVISOR_DIR}/notify.sh" "Claude Code Updated" \
      "Version ${current_version}: All hooks validated OK." 2>/dev/null || true
  fi

  echo "$current_version" > "$VERSION_FILE"
fi
