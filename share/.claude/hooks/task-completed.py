#!/usr/bin/env python3
"""
Layer A + X — TaskCompleted hook: blocks premature task completion.

Prevents TaskCreate tasks from being marked complete unless the session's
swarm has all agents with guid_seen=True. Falls back to allowing through
after stop_attempt_max to prevent infinite loops.
"""
import sys
import json
import os
import time

CONFIG_PATH = os.path.expanduser("~/.claude/supervisor/config.json")
REGISTRY_PATH = os.path.expanduser("~/.claude/supervisor/swarm-registry.json")
ATTEMPTS_DIR = os.path.expanduser("~/.claude/supervisor/stop-attempts")

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {"completion_token": os.environ.get("CLAUDE_COMPLETION_TOKEN",
                "e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70"),
                "stop_attempt_max": 3}

def check_swarm_complete(session_id):
    """Returns (all_done, incomplete_count)."""
    try:
        with open(REGISTRY_PATH) as f:
            registry = json.load(f)
        swarm = registry.get("swarms", {}).get(session_id, {})
        agents = swarm.get("agents", {})
        if not agents:
            return True, 0
        incomplete = [aid for aid, info in agents.items()
                      if info.get("status") == "active" and not info.get("guid_seen")]
        return len(incomplete) == 0, len(incomplete)
    except Exception:
        return True, 0  # Allow through if registry unavailable

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cfg = load_config()
max_attempts = cfg.get("stop_attempt_max", 3)
session_id = data.get("session_id", "unknown")

all_done, incomplete = check_swarm_complete(session_id)

if not all_done:
    # Check attempt counter
    key = f"task-complete-{session_id}"
    path = os.path.join(ATTEMPTS_DIR, key)
    try:
        with open(path) as f:
            count = int(f.read().strip())
    except Exception:
        count = 0
    count += 1
    if count < max_attempts:
        with open(path, "w") as f:
            f.write(str(count))
        print(json.dumps({
            "decision": "block",
            "reason": f"{incomplete} sub-agent(s) have not completed yet. Do not mark this task done until all agents finish."
        }))
        sys.exit(2)
    else:
        try:
            os.remove(path)
        except Exception:
            pass

sys.exit(0)
