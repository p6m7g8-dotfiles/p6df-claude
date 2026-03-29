#!/usr/bin/env python3
"""
Layer A — Stop hook: prevents the main agent from stopping prematurely.

Logic: block ALL stops unless the completion token appears on its own line
at the end of the response. stop_hook_active is the infinite-loop safety
valve — after stop_attempt_max consecutive blocks we allow through once.

Config: ~/.claude/supervisor/config.json
"""
import sys
import json
import os
import re
import time

CONFIG_PATH = os.path.expanduser("~/.claude/supervisor/config.json")
ATTEMPTS_DIR = os.path.expanduser("~/.claude/supervisor/stop-attempts")

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {"completion_token": os.environ.get("CLAUDE_COMPLETION_TOKEN", "e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70"),
                "stop_attempt_max": 3}

def get_attempt_count(session_id):
    os.makedirs(ATTEMPTS_DIR, exist_ok=True)
    path = os.path.join(ATTEMPTS_DIR, session_id)
    try:
        with open(path) as f:
            return int(f.read().strip())
    except Exception:
        return 0

def set_attempt_count(session_id, count):
    os.makedirs(ATTEMPTS_DIR, exist_ok=True)
    path = os.path.join(ATTEMPTS_DIR, session_id)
    with open(path, "w") as f:
        f.write(str(count))

def reset_attempt_count(session_id):
    path = os.path.join(ATTEMPTS_DIR, session_id)
    try:
        os.remove(path)
    except Exception:
        pass

def token_on_own_line(msg, token):
    """Token must appear on its own line (possibly the last line)."""
    return bool(re.search(r'^\s*' + re.escape(token) + r'\s*$', msg, re.MULTILINE))

def log_intervention(event, session_id, detail=""):
    log_path = os.path.expanduser("~/.claude/supervisor/interventions.log")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": event, "layer": "A-stop", "session_id": session_id,
                        "detail": detail})
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
max_attempts = cfg.get("stop_attempt_max", 3)
active = data.get("stop_hook_active", False)
msg = data.get("last_assistant_message", "")
session_id = data.get("session_id", "unknown")

# Token present on its own line → task is done
if token and token_on_own_line(msg, token):
    reset_attempt_count(session_id)
    sys.exit(0)

# Safety valve: if already looping, check attempt counter
if active:
    count = get_attempt_count(session_id)
    count += 1
    set_attempt_count(session_id, count)
    if count >= max_attempts:
        # Allow through after max consecutive blocks to prevent infinite loop
        log_intervention("stop_allowed_max_attempts", session_id, f"count={count}")
        reset_attempt_count(session_id)
        sys.exit(0)

# Block — task not complete
log_intervention("stop_blocked", session_id, f"active={active} msg_len={len(msg)}")
print(json.dumps({
    "decision": "block",
    "reason": (
        f"Task is not complete — completion token not found. "
        f"Continue executing until the task is fully done, "
        f"then write the token {token} on its own line as the last line of your response."
    )
}))
sys.exit(2)
