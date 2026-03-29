#!/usr/bin/env python3
"""
Layer A/L — PreCompact hook: snapshots task state before compaction.

Writes a fresh task-anchor.txt immediately before compaction fires.
PostCompact reads this file to restore context. PreCompact cannot block.
"""
import sys
import json
import os
import time

TASK_ANCHOR = os.path.expanduser("~/.claude/supervisor/task-anchor.txt")
TASK_STATE = os.path.expanduser("~/.claude/supervisor/task-state.jsonl")

def get_last_n_actions(n=10):
    """Read last N entries from task-state.jsonl for anchor."""
    entries = []
    try:
        with open(TASK_STATE) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except Exception:
                        pass
    except Exception:
        pass
    return entries[-n:] if entries else []

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

session_id = data.get("session_id", "unknown")
transcript_path = data.get("transcript_path", "")

# Build anchor from recent actions
actions = get_last_n_actions(10)
lines = [f"Session {session_id[:8]} — pre-compaction snapshot at {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}"]
if actions:
    lines.append("Recent actions:")
    for a in actions:
        ts = a.get("ts", "")[:16]
        tool = a.get("tool", "")
        target = a.get("file_or_action", "")
        lines.append(f"  [{ts}] {tool}: {target}")

try:
    os.makedirs(os.path.dirname(TASK_ANCHOR), exist_ok=True)
    with open(TASK_ANCHOR, "w") as f:
        f.write("\n".join(lines))
except Exception:
    pass

sys.exit(0)
