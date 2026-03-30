#!/usr/bin/env bash
# Layer AB: Multi-pane swarm launcher.
# Creates a tmux session with a pane per swarm agent + coordinator + monitor pane.
set -euo pipefail

SESSION="${CLAUDE_SWARM_SESSION:-claude-swarm}"
SUPERVISOR_DIR="$HOME/.claude/supervisor"
REGISTRY="$SUPERVISOR_DIR/swarm-registry.json"

usage() {
    cat <<EOF
Usage: $0 [options] [-- claude-args...]

Options:
  -n, --agents N       Number of worker agent panes (default: 2)
  -s, --session NAME   tmux session name (default: claude-swarm)
  -t, --task TEXT      Initial task prompt for coordinator
  -h, --help           Show this help

Layout:
  Pane 0: coordinator (main Claude instance)
  Pane 1..N: worker agents
  Pane N+1: swarm-monitor (always-visible status)
EOF
    exit 0
}

N_AGENTS=2
TASK=""
CLAUDE_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--agents) N_AGENTS="$2"; shift 2 ;;
        -s|--session) SESSION="$2"; shift 2 ;;
        -t|--task) TASK="$2"; shift 2 ;;
        -h|--help) usage ;;
        --) shift; CLAUDE_ARGS=("$@"); break ;;
        *) echo "Unknown arg: $1"; usage ;;
    esac
done

mkdir -p "$SUPERVISOR_DIR/logs"

init_registry() {
    python3 - <<PYEOF
import json, os, time
from pathlib import Path
reg = {"agents": {}, "created_at": time.time(), "session": "$SESSION"}
tmp = "$REGISTRY.tmp"
with open(tmp, "w") as f:
    json.dump(reg, f, indent=2)
os.replace(tmp, "$REGISTRY")
print("Registry initialized")
PYEOF
}

register_pane() {
    local agent_id="$1"
    local pane_id="$2"
    local role="$3"
    python3 - <<PYEOF
import json, os, time, fcntl
from pathlib import Path
reg_path = Path("$REGISTRY")
lock_path = Path("$SUPERVISOR_DIR/swarm-registry.lock")
with open(lock_path, "w") as lf:
    fcntl.flock(lf, fcntl.LOCK_EX)
    try:
        reg = json.loads(reg_path.read_text()) if reg_path.exists() else {"agents": {}}
        reg["agents"]["$agent_id"] = {
            "pane_id": "$pane_id",
            "role": "$role",
            "started_at": time.time(),
            "guid_seen": False,
            "active": True,
        }
        tmp = str(reg_path) + ".tmp"
        with open(tmp, "w") as f:
            json.dump(reg, f, indent=2)
        os.replace(tmp, str(reg_path))
    finally:
        fcntl.flock(lf, fcntl.LOCK_UN)
PYEOF
}

# Kill existing session if any
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Killing existing session: $SESSION"
    tmux kill-session -t "$SESSION"
fi

echo "Creating swarm session: $SESSION (coordinator + $N_AGENTS agents + monitor)"

# Create session with coordinator pane
tmux new-session -d -s "$SESSION" -n "coordinator"
COORD_PANE=$(tmux display-message -p -t "$SESSION:coordinator" '#{pane_id}')

init_registry
register_pane "coordinator" "$COORD_PANE" "coordinator"

# Create worker panes
for i in $(seq 1 "$N_AGENTS"); do
    AGENT_ID="worker-$i"
    tmux split-window -t "$SESSION:coordinator" -v
    AGENT_PANE=$(tmux display-message -p -t "$SESSION:coordinator" '#{pane_id}')
    register_pane "$AGENT_ID" "$AGENT_PANE" "worker"
    echo "Created worker pane $i: $AGENT_PANE"
done

# Tiled layout for even split
tmux select-layout -t "$SESSION:coordinator" tiled

# Create monitor pane in a separate window
tmux new-window -t "$SESSION" -n "monitor"
MONITOR_PANE=$(tmux display-message -p -t "$SESSION:monitor" '#{pane_id}')

# Start swarm-monitor in monitor pane
tmux send-keys -t "$MONITOR_PANE" "python3 $SUPERVISOR_DIR/swarm-monitor.py 2>&1 | tee $SUPERVISOR_DIR/logs/swarm-monitor.log" Enter

# Send Claude launch commands to coordinator and workers
COORD_CMD="claude"
if [ -n "$TASK" ]; then
    COORD_CMD="claude --print '$TASK'"
fi
if [ "${#CLAUDE_ARGS[@]}" -gt 0 ]; then
    COORD_CMD="claude ${CLAUDE_ARGS[*]}"
fi

echo "Launching coordinator: $COORD_CMD"
tmux send-keys -t "$COORD_PANE" "$COORD_CMD" Enter

# Workers start idle (coordinator will spawn them as needed)
for i in $(seq 1 "$N_AGENTS"); do
    WORKER_PANE_IDX=$((i))
    tmux send-keys -t "$SESSION:coordinator.$WORKER_PANE_IDX" \
        "echo 'Worker $i ready — waiting for coordinator instructions'" Enter
done

# Write swarm active-session
python3 - <<PYEOF
import json, os, time
from pathlib import Path
data = {
    "session": "$SESSION",
    "coordinator_pane": "$COORD_PANE",
    "monitor_pane": "$MONITOR_PANE",
    "n_agents": $N_AGENTS,
    "started_at": time.time(),
}
path = Path("$SUPERVISOR_DIR/active-session.json")
tmp = str(path) + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, str(path))
PYEOF

echo ""
echo "Swarm ready:"
echo "  Session:     $SESSION"
echo "  Coordinator: $COORD_PANE"
echo "  Monitor:     $MONITOR_PANE"
echo "  Workers:     $N_AGENTS"
echo ""
echo "Attach: tmux attach -t $SESSION"
