#!/usr/bin/env bash
# Layer T: Daily audit report — summarizes never-stop system health
set -euo pipefail

SUPERVISOR_DIR="$HOME/.claude/supervisor"
LOG_DIR="$SUPERVISOR_DIR/logs"
AUDIT_DIR="$SUPERVISOR_DIR/audits"
mkdir -p "$AUDIT_DIR"

DATE=$(date +%Y-%m-%d)
REPORT="$AUDIT_DIR/audit-$DATE.txt"
TOKEN="e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70"

exec > "$REPORT" 2>&1

echo "=== Claude Never-Stop Audit Report: $DATE ==="
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# --- Hook health ---
echo "## Hook Compilation Status"
HOOK_ERRORS=0
for f in "$HOME/.claude/hooks/"*.py; do
    if ! python3 -m py_compile "$f" 2>/dev/null; then
        echo "  FAIL: $f"
        HOOK_ERRORS=$((HOOK_ERRORS + 1))
    fi
done
if [ "$HOOK_ERRORS" -eq 0 ]; then
    echo "  All hooks compile OK"
fi
echo ""

# --- Daemon status ---
echo "## Daemon Status"
DAEMONS=(monitor.py supervisor.py credential-monitor.py billing-governor.py message-bus.py resource-governor.py)
for d in "${DAEMONS[@]}"; do
    if pgrep -f "$d" >/dev/null 2>&1; then
        echo "  RUNNING: $d"
    else
        echo "  DEAD:    $d"
    fi
done
echo ""

# --- Launchd plists ---
echo "## LaunchD Plists"
PLISTS=(
    com.p6df.claude-monitor
    com.p6df.claude-supervisor
    com.p6df.claude-credential-monitor
    com.p6df.claude-billing-governor
    com.p6df.claude-message-bus
)
for p in "${PLISTS[@]}"; do
    if launchctl list "$p" >/dev/null 2>&1; then
        echo "  LOADED:   $p"
    else
        echo "  UNLOADED: $p"
    fi
done
echo ""

# --- Symlink health ---
echo "## Critical Symlink Health"
declare -A SYMLINKS=(
    ["$HOME/.claude/settings.json"]="settings.json"
    ["$HOME/.claude/CLAUDE.md"]="CLAUDE.md"
    ["$HOME/.claude/hooks"]="hooks dir"
    ["$HOME/.claude/supervisor"]="supervisor dir"
)
for target in "${!SYMLINKS[@]}"; do
    label="${SYMLINKS[$target]}"
    if [ -L "$target" ]; then
        echo "  SYMLINK: $label -> $(readlink "$target")"
    elif [ -e "$target" ]; then
        echo "  REAL:    $label (not a symlink — may be stale)"
    else
        echo "  MISSING: $label"
    fi
done
echo ""

# --- Stop attempts (last 24h) ---
echo "## Stop Attempt Counters (last 24h)"
STOP_DIR="$SUPERVISOR_DIR/stop-attempts"
if [ -d "$STOP_DIR" ]; then
    COUNT=$(find "$STOP_DIR" -newer "$SUPERVISOR_DIR/audit-last-run" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  Sessions with stop attempts since last audit: $COUNT"
    # Show sessions with high counts
    for f in "$STOP_DIR"/*; do
        [ -f "$f" ] || continue
        val=$(cat "$f" 2>/dev/null || echo 0)
        if [ "$val" -ge 2 ] 2>/dev/null; then
            echo "  HIGH: $(basename "$f") = $val attempts"
        fi
    done
else
    echo "  No stop-attempts directory"
fi
echo ""

# --- Sentinel files ---
echo "## Sentinel Files"
SENTINELS=(
    "$SUPERVISOR_DIR/spawn-blocked"
    "$SUPERVISOR_DIR/billing-blocked"
    "$SUPERVISOR_DIR/cred-refresh-needed"
)
for s in "${SENTINELS[@]}"; do
    if [ -f "$s" ]; then
        echo "  ACTIVE: $(basename "$s") — $(cat "$s" | head -1)"
    fi
done
[ "${#SENTINELS[@]}" -gt 0 ] || echo "  No active sentinels"
echo ""

# --- Token hit rate (from session logs) ---
echo "## Completion Token Activity"
if [ -d "$LOG_DIR" ]; then
    TOTAL_STOPS=$(grep -r "stop_hook" "$LOG_DIR/" 2>/dev/null | wc -l | tr -d ' ')
    TOKEN_HITS=$(grep -r "$TOKEN" "$LOG_DIR/" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Total stop hook fires: $TOTAL_STOPS"
    echo "  Completions with token: $TOKEN_HITS"
else
    echo "  No log directory"
fi
echo ""

# --- Resource state ---
echo "## Resource State"
RESOURCE_STATE="$SUPERVISOR_DIR/resource-state.json"
if [ -f "$RESOURCE_STATE" ]; then
    python3 - <<'PYEOF'
import json, sys
from pathlib import Path
state = json.loads(Path.home().joinpath(".claude/supervisor/resource-state.json").read_text())
u = state.get("usage", {})
print(f"  Load 1m:    {u.get('load_1m', 'N/A')}")
print(f"  Memory:     {u.get('memory_pct', 'N/A'):.0f}%" if isinstance(u.get('memory_pct'), float) else f"  Memory:     N/A")
print(f"  Disk:       {u.get('disk_pct', 'N/A'):.0f}%" if isinstance(u.get('disk_pct'), float) else f"  Disk:       N/A")
print(f"  Blocked:    {state.get('blocked', False)}")
PYEOF
else
    echo "  resource-state.json not found"
fi
echo ""

# --- Summary ---
echo "## Summary"
ISSUES=0
for d in "${DAEMONS[@]}"; do
    pgrep -f "$d" >/dev/null 2>&1 || ISSUES=$((ISSUES + 1))
done
[ "$HOOK_ERRORS" -eq 0 ] || ISSUES=$((ISSUES + HOOK_ERRORS))
for s in "${SENTINELS[@]}"; do
    [ -f "$s" ] && ISSUES=$((ISSUES + 1))
done

if [ "$ISSUES" -eq 0 ]; then
    echo "  STATUS: HEALTHY — all systems operational"
else
    echo "  STATUS: DEGRADED — $ISSUES issue(s) found"
fi
echo ""

# Update last-run marker
touch "$SUPERVISOR_DIR/audit-last-run"

echo "Report saved to: $REPORT"

# Send notification
osascript -e "display notification \"Audit complete: $ISSUES issue(s)\" with title \"Claude Audit\"" 2>/dev/null \
    || tput bel 2>/dev/null || true
