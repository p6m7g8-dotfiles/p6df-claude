#!/usr/bin/env python3
"""
Layer A + X — PostToolUse hook (Agent matcher): checks sub-agent results for
the completion token and updates swarm registry.

If the sub-agent returned without the token, injects feedback to the parent
so it knows the sub-agent may not have fully completed.
"""
import sys
import json
import os
import re
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

def token_on_own_line(msg, token):
    return bool(re.search(r'^\s*' + re.escape(token) + r'\s*$', msg, re.MULTILINE))

def update_agent_guid(session_id, agent_id, guid_seen):
    try:
        with open(REGISTRY_LOCK, "w") as lf:
            fcntl.flock(lf, fcntl.LOCK_EX)
            try:
                try:
                    with open(REGISTRY_PATH) as f:
                        registry = json.load(f)
                except Exception:
                    return
                swarms = registry.get("swarms", {})
                if session_id in swarms:
                    agents = swarms[session_id].get("agents", {})
                    if agent_id in agents:
                        agents[agent_id]["guid_seen"] = guid_seen
                        agents[agent_id]["status"] = "complete" if guid_seen else "incomplete"
                        agents[agent_id]["last_heartbeat"] = time.time()
                tmp = REGISTRY_PATH + ".tmp"
                with open(tmp, "w") as f:
                    json.dump(registry, f, indent=2)
                os.replace(tmp, REGISTRY_PATH)
            finally:
                fcntl.flock(lf, fcntl.LOCK_UN)
    except Exception:
        pass

def log_intervention(event, detail=""):
    log_path = os.path.expanduser("~/.claude/supervisor/interventions.log")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": event, "layer": "A-post-tool-agent", "detail": detail})
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
session_id = data.get("session_id", "unknown")
tool_response = str(data.get("tool_response", ""))
agent_id = data.get("agent_id", "unknown")

guid_seen = token_on_own_line(tool_response, token)
update_agent_guid(session_id, agent_id, guid_seen)

if not guid_seen and token:
    log_intervention("agent_no_token", f"agent={agent_id[:8]}")
    print(json.dumps({
        "decision": "block",
        "reason": (
            f"The sub-agent you just ran did not write the completion token. "
            f"It may not have fully completed its task. Review its output and "
            f"either rerun it or complete the remaining work yourself."
        )
    }))
    sys.exit(2)

sys.exit(0)
