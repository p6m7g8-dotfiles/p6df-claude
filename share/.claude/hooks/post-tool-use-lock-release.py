#!/usr/bin/env python3
"""
Layer AA — PostToolUse + PostToolUseFailure hook (Edit|Write|MultiEdit matcher):
releases swarm write locks after file operations complete (success or failure).
"""
import sys
import json
import os
import time
import fcntl

REGISTRY_PATH = os.path.expanduser("~/.claude/supervisor/swarm-locks.json")
LOCK_FILE = os.path.expanduser("~/.claude/supervisor/.locks.lock")

def release_lock(file_path, agent_id):
    try:
        with open(LOCK_FILE, "w") as lf:
            fcntl.flock(lf, fcntl.LOCK_EX)
            try:
                locks = {}
                try:
                    with open(REGISTRY_PATH) as f:
                        locks = json.load(f)
                except Exception:
                    pass
                if file_path in locks and locks[file_path].get("agent_id") == agent_id:
                    del locks[file_path]
                    tmp = REGISTRY_PATH + ".tmp"
                    with open(tmp, "w") as f:
                        json.dump(locks, f)
                    os.replace(tmp, REGISTRY_PATH)
            finally:
                fcntl.flock(lf, fcntl.LOCK_UN)
    except Exception:
        pass

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool_input = data.get("tool_input", {})
file_path = tool_input.get("file_path", tool_input.get("path", ""))
agent_id = data.get("agent_id", data.get("session_id", "unknown"))

if file_path:
    release_lock(file_path, agent_id)

sys.exit(0)
