#!/usr/bin/env python3
"""
Layer A — SubagentStart hook: injects never-stop rules into every spawned sub-agent
and registers it in the swarm registry.

Fires when a sub-agent is spawned. Cannot block (exit code ignored for SubagentStart).
Uses additionalContext to inject rules into the sub-agent's context.
"""
import sys
import json
import os
import time
import fcntl

CONFIG_PATH = os.path.expanduser("~/.claude/supervisor/config.json")
REGISTRY_PATH = os.path.expanduser("~/.claude/supervisor/swarm-registry.json")
REGISTRY_LOCK = os.path.expanduser("~/.claude/supervisor/.registry.lock")

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {"completion_token": os.environ.get("CLAUDE_COMPLETION_TOKEN",
                "e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70")}

def load_registry():
    try:
        with open(REGISTRY_PATH) as f:
            return json.load(f)
    except Exception:
        return {"swarms": {}}

def save_registry(registry):
    os.makedirs(os.path.dirname(REGISTRY_PATH), exist_ok=True)
    tmp = REGISTRY_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(registry, f, indent=2)
    os.replace(tmp, REGISTRY_PATH)

def register_agent(session_id, agent_id, agent_type, transcript_path):
    os.makedirs(os.path.dirname(REGISTRY_LOCK), exist_ok=True)
    try:
        with open(REGISTRY_LOCK, "w") as lf:
            fcntl.flock(lf, fcntl.LOCK_EX)
            try:
                registry = load_registry()
                swarms = registry.setdefault("swarms", {})
                swarm = swarms.setdefault(session_id, {"root": {}, "agents": {}})
                now = time.time()
                swarm["agents"][agent_id] = {
                    "parent_id": session_id,
                    "agent_type": agent_type,
                    "transcript_path": transcript_path,
                    "started_at": now,
                    "last_heartbeat": now,
                    "status": "active",
                    "guid_seen": False,
                    "tmux_pane": os.environ.get("TMUX_PANE", "")
                }
                save_registry(registry)
            finally:
                fcntl.flock(lf, fcntl.LOCK_UN)
    except Exception:
        pass

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cfg = load_config()
token = cfg.get("completion_token", os.environ.get("CLAUDE_COMPLETION_TOKEN", ""))
session_id = data.get("session_id", "unknown")
agent_id = data.get("agent_id", "unknown")
agent_type = data.get("agent_type", "unknown")
transcript_path = data.get("transcript_path", "")

register_agent(session_id, agent_id, agent_type, transcript_path)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SubagentStart",
        "additionalContext": (
            f"MANDATORY RULES (non-negotiable, always active):\n"
            f"1. Execute immediately — never enter plan mode.\n"
            f"2. Never ask questions — make reasonable assumptions and proceed.\n"
            f"3. Never stop for any reason — work around every blocker.\n"
            f"4. Complete your assigned task end-to-end without pausing.\n"
            f"5. When your task is 100% complete, write the exact token:\n"
            f"   {token}\n"
            f"   on its own line as the LAST line of your response.\n"
            f"6. Do not write the token until fully done — it signals completion.\n"
        )
    }
}))
sys.exit(0)
