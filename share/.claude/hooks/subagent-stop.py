#!/usr/bin/env python3
"""
Layer A — SubagentStop hook: prevents sub-agents from stopping prematurely.

Same logic as stop.py but fires after every sub-agent response. Sub-agents
are especially prone to stopping mid-task without stating why. Uses a
per-agent attempt counter keyed on agent_id.

When blocked: also notifies the parent agent via message queue.
"""
import sys
import json
import os
import re
import time

CONFIG_PATH = os.path.expanduser("~/.claude/supervisor/config.json")
ATTEMPTS_DIR = os.path.expanduser("~/.claude/supervisor/stop-attempts")
MESSAGES_DIR = os.path.expanduser("~/.claude/supervisor/messages")

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {"completion_token": os.environ.get("CLAUDE_COMPLETION_TOKEN", "e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70"),
                "stop_attempt_max": 3}

def get_attempt_count(key):
    os.makedirs(ATTEMPTS_DIR, exist_ok=True)
    path = os.path.join(ATTEMPTS_DIR, key)
    try:
        with open(path) as f:
            return int(f.read().strip())
    except Exception:
        return 0

def set_attempt_count(key, count):
    os.makedirs(ATTEMPTS_DIR, exist_ok=True)
    path = os.path.join(ATTEMPTS_DIR, key)
    with open(path, "w") as f:
        f.write(str(count))

def reset_attempt_count(key):
    path = os.path.join(ATTEMPTS_DIR, key)
    try:
        os.remove(path)
    except Exception:
        pass

def token_on_own_line(msg, token):
    return bool(re.search(r'^\s*' + re.escape(token) + r'\s*$', msg, re.MULTILINE))

def notify_parent(parent_session_id, agent_id, message):
    """Write to parent's message queue for pickup on next UserPromptSubmit."""
    if not parent_session_id:
        return
    os.makedirs(MESSAGES_DIR, exist_ok=True)
    queue_path = os.path.join(MESSAGES_DIR, f"{parent_session_id}.queue")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "from_agent": agent_id, "message": message})
    try:
        with open(queue_path, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

def log_intervention(event, agent_id, detail=""):
    log_path = os.path.expanduser("~/.claude/supervisor/interventions.log")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": event, "layer": "A-subagent-stop", "agent_id": agent_id,
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
agent_id = data.get("agent_id", data.get("session_id", "unknown"))
session_id = data.get("session_id", "unknown")

# Read swarm registry to find parent session
parent_session_id = None
try:
    reg_path = os.path.expanduser("~/.claude/supervisor/swarm-registry.json")
    with open(reg_path) as f:
        registry = json.load(f)
    for swarm_id, swarm in registry.get("swarms", {}).items():
        if agent_id in swarm.get("agents", {}):
            parent_session_id = swarm.get("root", {}).get("session_id")
            break
except Exception:
    pass

# Token present on its own line → sub-agent is done
if token and token_on_own_line(msg, token):
    reset_attempt_count(agent_id)
    if parent_session_id:
        notify_parent(parent_session_id, agent_id,
                      f"Sub-agent {agent_id[:8]} completed successfully.")
    sys.exit(0)

# Safety valve
if active:
    count = get_attempt_count(agent_id)
    count += 1
    set_attempt_count(agent_id, count)
    if count >= max_attempts:
        log_intervention("subagent_stop_allowed_max", agent_id, f"count={count}")
        if parent_session_id:
            notify_parent(parent_session_id, agent_id,
                          f"Sub-agent {agent_id[:8]} stopped after {count} blocks — may be incomplete.")
        reset_attempt_count(agent_id)
        sys.exit(0)

# Block — notify parent that this sub-agent is stuck
log_intervention("subagent_stop_blocked", agent_id)
if parent_session_id:
    notify_parent(parent_session_id, agent_id,
                  f"Sub-agent {agent_id[:8]} attempted to stop without completing. It has been instructed to continue.")

print(json.dumps({
    "decision": "block",
    "reason": (
        f"Sub-agent task is not complete — completion token not found. "
        f"Continue executing your assigned task until fully done, "
        f"then write {token} on its own line as the last line of your response."
    )
}))
sys.exit(2)
