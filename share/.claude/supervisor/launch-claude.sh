#!/usr/bin/env bash
# Layer Q: Dedicated tmux session launcher for Claude Code.
# Creates/reuses a tmux session so monitor.py always has a pane to watch.
set -euo pipefail

SESSION="${CLAUDE_TMUX_SESSION:-claude}"
WINDOW="${CLAUDE_TMUX_WINDOW:-main}"
SUPERVISOR_DIR="$HOME/.claude/supervisor"

start_daemons() {
    # Ensure all daemons are running (supervisor.py will keep them alive,
    # but start them here on first launch before supervisor itself starts)
    local daemons=(
        "monitor.py"
        "swarm-monitor.py"
        "supervisor.py"
        "credential-monitor.py"
        "billing-governor.py"
        "resource-governor.py"
        "message-bus.py"
    )
    for d in "${daemons[@]}"; do
        if ! pgrep -f "$d" >/dev/null 2>&1; then
            python3 "$SUPERVISOR_DIR/$d" >> "$SUPERVISOR_DIR/logs/${d%.py}.log" 2>&1 &
            echo "Started $d (pid $!)"
        else
            echo "Already running: $d"
        fi
    done
}

write_active_session() {
    local pane_id="$1"
    local session_file="$SUPERVISOR_DIR/active-session.json"
    python3 - <<PYEOF
import json, os, time
from pathlib import Path
data = {
    "session": "$SESSION",
    "window": "$WINDOW",
    "pane_id": "$pane_id",
    "started_at": time.time(),
    "pid": os.getpid(),
}
tmp = "$session_file.tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, "$session_file")
PYEOF
}

# Create tmux session if not exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Creating tmux session: $SESSION"
    tmux new-session -d -s "$SESSION" -n "$WINDOW"
else
    echo "Reusing tmux session: $SESSION"
fi

# Get pane id
PANE_ID=$(tmux display-message -p -t "$SESSION:$WINDOW" '#{pane_id}' 2>/dev/null || echo "%0")

# Write active session info
mkdir -p "$SUPERVISOR_DIR/logs"
write_active_session "$PANE_ID"

# Start background daemons
start_daemons

# Attach to or create the working window
if [ "${1:-}" = "--attach" ]; then
    exec tmux attach-session -t "$SESSION"
elif [ "${1:-}" = "--new-window" ]; then
    WINDOW_NAME="${2:-claude-$(date +%H%M%S)}"
    tmux new-window -t "$SESSION" -n "$WINDOW_NAME"
    PANE_ID=$(tmux display-message -p -t "$SESSION:$WINDOW_NAME" '#{pane_id}')
    write_active_session "$PANE_ID"
    exec tmux attach-session -t "$SESSION:$WINDOW_NAME"
else
    echo "Session '$SESSION' ready. Pane: $PANE_ID"
    echo "Run: tmux attach -t $SESSION"
    echo "Or:  $0 --attach"
fi
