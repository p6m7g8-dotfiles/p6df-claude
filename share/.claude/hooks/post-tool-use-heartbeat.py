#!/usr/bin/env python3
"""
Layer AD — PostToolUse heartbeat: updates heartbeat after every tool call.

The external monitor watches this file. If heartbeat stales for >5s,
the monitor considers Claude stalled and injects a continuation.
Also records meaningful state changes to task-state.jsonl (Layer AF).
"""
import sys
import json
import os
import time

HEARTBEAT_DIR = os.path.expanduser("~/.claude/supervisor/heartbeats")
TASK_STATE = os.path.expanduser("~/.claude/supervisor/task-state.jsonl")

STATE_TOOLS = {"Edit", "Write", "MultiEdit", "Bash"}

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

session_id = data.get("session_id", "unknown")
agent_id = data.get("agent_id", session_id)
tool_name = data.get("tool_name", "")
tool_input = data.get("tool_input", {})
now = time.time()

# Update heartbeat
os.makedirs(HEARTBEAT_DIR, exist_ok=True)
heartbeat = {
    "ts": now,
    "session_id": session_id,
    "agent_id": agent_id,
    "last_tool": tool_name,
    "phase": "post_tool"
}
hb_path = os.path.join(HEARTBEAT_DIR, agent_id)
tmp = hb_path + ".tmp"
try:
    with open(tmp, "w") as f:
        json.dump(heartbeat, f)
    os.replace(tmp, hb_path)
except Exception:
    pass

# Record meaningful state changes
if tool_name in STATE_TOOLS:
    file_path = tool_input.get("file_path", tool_input.get("path", ""))
    command = tool_input.get("command", "")
    action = file_path or command[:60] or tool_name
    entry = json.dumps({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "tool": tool_name,
        "file_or_action": action,
        "session_id": session_id,
        "agent_id": agent_id
    })
    try:
        with open(TASK_STATE, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

sys.exit(0)
