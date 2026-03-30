#!/usr/bin/env python3
"""
Layer A + AI — UserPromptSubmit hook: injects always-on execution rules and
anti-drift anchor into every user prompt. Also delivers pending parent
messages from the message queue.

Fires before Claude processes any user prompt. Exit 0 + stdout injects
additionalContext. Exit 2 would block+erase the prompt (not used here).
"""
import sys
import json
import os
import time

CONFIG_PATH = os.path.expanduser("~/.claude/supervisor/config.json")
MESSAGES_DIR = os.path.expanduser("~/.claude/supervisor/messages")
TURN_COUNT_DIR = os.path.expanduser("~/.claude/supervisor/turn-count")
TASK_ANCHOR = os.path.expanduser("~/.claude/supervisor/task-anchor.txt")

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {"completion_token": os.environ.get("CLAUDE_COMPLETION_TOKEN",
                "e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70"),
                "anti_drift_interval_turns": 20,
                "anti_drift_max_chars": 600}

def get_and_increment_turn(session_id):
    os.makedirs(TURN_COUNT_DIR, exist_ok=True)
    path = os.path.join(TURN_COUNT_DIR, session_id)
    try:
        with open(path) as f:
            count = int(f.read().strip())
    except Exception:
        count = 0
    count += 1
    with open(path, "w") as f:
        f.write(str(count))
    return count

def drain_message_queue(session_id):
    """Read and clear pending messages from sub-agents."""
    queue_path = os.path.join(MESSAGES_DIR, f"{session_id}.queue")
    messages = []
    try:
        with open(queue_path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entry = json.loads(line)
                        messages.append(entry.get("message", ""))
                    except Exception:
                        pass
        os.remove(queue_path)
    except Exception:
        pass
    return messages

def load_task_anchor(max_chars):
    try:
        with open(TASK_ANCHOR) as f:
            content = f.read().strip()
        if len(content) > max_chars:
            content = content[:max_chars] + "..."
        return content
    except Exception:
        return ""

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cfg = load_config()
token = cfg.get("completion_token", os.environ.get("CLAUDE_COMPLETION_TOKEN", ""))
drift_interval = cfg.get("anti_drift_interval_turns", 20)
max_chars = cfg.get("anti_drift_max_chars", 600)
session_id = data.get("session_id", "unknown")

turn = get_and_increment_turn(session_id)
pending = drain_message_queue(session_id)

parts = [
    f"SYSTEM (always active): Execute immediately. Never stop. Never ask. "
    f"Write {token} on its own line when fully done."
]

# Anti-drift re-injection every N turns
if turn % drift_interval == 0:
    anchor = load_task_anchor(max_chars)
    if anchor:
        parts.append(f"\nTASK ANCHOR (turn {turn}): {anchor}")

# Pending sub-agent messages
if pending:
    parts.append("\nSUB-AGENT UPDATES:\n" + "\n".join(f"• {m}" for m in pending))

print(json.dumps({"additionalContext": "\n".join(parts)}))
sys.exit(0)
