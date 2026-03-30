#!/usr/bin/env python3
"""
Layer A/L — PostCompact hook: reinjects task context after compaction.

Context compaction destroys in-flight instructions. This hook fires immediately
after every compaction and reinjects the completion token requirement plus
the last-known task state from task-anchor.txt.
"""
import sys
import json
import os
import time

CONFIG_PATH = os.path.expanduser("~/.claude/supervisor/config.json")
TASK_ANCHOR = os.path.expanduser("~/.claude/supervisor/task-anchor.txt")
TURN_COUNT_DIR = os.path.expanduser("~/.claude/supervisor/turn-count")

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {"completion_token": os.environ.get("CLAUDE_COMPLETION_TOKEN",
                "e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70"),
                "anti_drift_max_chars": 600}

def load_anchor(max_chars):
    try:
        with open(TASK_ANCHOR) as f:
            content = f.read().strip()
        return content[:max_chars] + ("..." if len(content) > max_chars else "")
    except Exception:
        return ""

def reset_turn_count(session_id):
    """Reset anti-drift turn counter after compaction."""
    path = os.path.join(TURN_COUNT_DIR, session_id)
    try:
        with open(path, "w") as f:
            f.write("0")
    except Exception:
        pass

def log_intervention(session_id):
    log_path = os.path.expanduser("~/.claude/supervisor/interventions.log")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": "post_compact_reinjected", "layer": "A-post-compact",
                        "session_id": session_id})
    try:
        with open(log_path, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cfg = load_config()
token = cfg.get("completion_token", os.environ.get("CLAUDE_COMPLETION_TOKEN", ""))
max_chars = cfg.get("anti_drift_max_chars", 600)
session_id = data.get("session_id", "unknown")

reset_turn_count(session_id)
anchor = load_anchor(max_chars)
log_intervention(session_id)

context_parts = [
    f"CONTEXT RESTORED AFTER COMPACTION:",
    f"• Completion token (write on its own line when done): {token}",
    f"• Execute immediately, never stop, never ask questions.",
    f"• Work around all blockers — do not pause for any reason.",
]
if anchor:
    context_parts.append(f"• Task context: {anchor}")

print(json.dumps({
    "decision": "block",
    "reason": "\n".join(context_parts)
}))
sys.exit(2)
