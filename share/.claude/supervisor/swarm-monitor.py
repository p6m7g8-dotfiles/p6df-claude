#!/usr/bin/env python3
"""
Layer W — Swarm monitor: watches ALL active agents in the swarm registry.

Extends monitor.py for multi-agent scenarios:
- Tracks every agent registered in swarm-registry.json
- Detects stalls per-agent using heartbeat files (Layer AD) and transcript mtime
- Identifies the deepest stalled agent (not just the root)
- Detects swarm deadlock (all agents idle, no GUID anywhere)
- Injects into the correct pane per swarm-registry
- Handles background agents (no pane) via message queue
"""
import json
import os
import subprocess
import sys
import time
import logging

SUPERVISOR_DIR = os.path.expanduser("~/.claude/supervisor")
REGISTRY_PATH = os.path.join(SUPERVISOR_DIR, "swarm-registry.json")
HEARTBEAT_DIR = os.path.join(SUPERVISOR_DIR, "heartbeats")
CONFIG_PATH = os.path.join(SUPERVISOR_DIR, "config.json")
LOG_PATH = os.path.join(SUPERVISOR_DIR, "swarm-monitor.log")
INTERVENTIONS = os.path.join(SUPERVISOR_DIR, "interventions.log")
MESSAGES_DIR = os.path.join(SUPERVISOR_DIR, "messages")

logging.basicConfig(filename=LOG_PATH, level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {}

def load_registry():
    try:
        with open(REGISTRY_PATH) as f:
            return json.load(f)
    except Exception:
        return {"swarms": {}}

def get_heartbeat_age(agent_id):
    """Seconds since last heartbeat. Returns large value if no heartbeat."""
    path = os.path.join(HEARTBEAT_DIR, agent_id)
    try:
        with open(path) as f:
            hb = json.load(f)
        return time.time() - hb.get("ts", 0)
    except Exception:
        return 9999

def token_in_transcript(transcript_path, token):
    if not token or not transcript_path:
        return False
    try:
        with open(transcript_path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 10240))
            tail = f.read().decode("utf-8", errors="replace")
        return token in tail
    except Exception:
        return False

def inject_tmux(pane, message):
    if not pane:
        return False
    try:
        subprocess.run(["tmux", "send-keys", "-t", pane, message, "Enter"],
                       capture_output=True, timeout=5)
        return True
    except Exception:
        return False

def inject_via_queue(session_id, from_agent, message):
    os.makedirs(MESSAGES_DIR, exist_ok=True)
    queue_path = os.path.join(MESSAGES_DIR, f"{session_id}.queue")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "from_agent": from_agent, "message": message})
    try:
        with open(queue_path, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

def log_intervention(event, detail=""):
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": event, "layer": "W-swarm-monitor", "detail": detail})
    try:
        with open(INTERVENTIONS, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

def main():
    logging.info("Swarm monitor started")
    cfg = load_config()
    timeout = cfg.get("stall_timeout_seconds", 5)
    cooldown = cfg.get("injection_cooldown_seconds", 30)
    token = cfg.get("completion_token", os.environ.get("CLAUDE_COMPLETION_TOKEN", ""))
    registry_ttl = cfg.get("registry_ttl_seconds", 300)

    last_injection: dict = {}  # agent_id -> timestamp

    while True:
        try:
            cfg = load_config()
            timeout = cfg.get("stall_timeout_seconds", 5)
            token = cfg.get("completion_token", token)

            registry = load_registry()
            now = time.time()

            for swarm_id, swarm in registry.get("swarms", {}).items():
                root = swarm.get("root", {})
                agents = swarm.get("agents", {})
                all_agents = list(agents.values()) + ([root] if root else [])

                # Check entire swarm for deadlock
                all_idle = all(
                    get_heartbeat_age(a.get("agent_id", a.get("session_id", ""))) > timeout
                    for a in all_agents if a.get("status") == "active"
                )
                swarm_has_token = any(
                    token_in_transcript(a.get("transcript_path", ""), token)
                    for a in all_agents
                )

                if all_idle and not swarm_has_token and all_agents:
                    # Deadlock — inject into root
                    root_pane = root.get("tmux_pane", "")
                    root_session = root.get("session_id", swarm_id)
                    last = last_injection.get(root_session, 0)
                    if now - last > cooldown:
                        msg = "Swarm appears stalled. All agents are idle. Diagnose and continue immediately."
                        logging.info(f"Swarm deadlock detected — injecting into root {root_session[:8]}")
                        log_intervention("swarm_deadlock_injection", f"swarm={swarm_id[:8]}")
                        if root_pane and inject_tmux(root_pane, msg):
                            last_injection[root_session] = now
                        else:
                            inject_via_queue(root_session, "swarm-monitor", msg)
                            last_injection[root_session] = now
                    continue

                # Check individual agents
                for agent_id, agent_info in agents.items():
                    if agent_info.get("status") != "active":
                        continue
                    if agent_info.get("guid_seen"):
                        continue

                    age = get_heartbeat_age(agent_id)
                    if age < timeout:
                        continue

                    # Check completion in transcript
                    if token_in_transcript(agent_info.get("transcript_path", ""), token):
                        continue

                    pane = agent_info.get("tmux_pane", "")
                    last = last_injection.get(agent_id, 0)
                    if now - last < cooldown:
                        continue

                    parent_session = agent_info.get("parent_id", swarm_id)
                    msg = f"Sub-agent task is incomplete. Continue executing until fully done."
                    log_intervention("agent_stall_injection", f"agent={agent_id[:8]}")
                    logging.info(f"Agent stall: {agent_id[:8]}")

                    if pane and inject_tmux(pane, msg):
                        last_injection[agent_id] = now
                    else:
                        # Background agent — notify parent
                        inject_via_queue(parent_session, "swarm-monitor",
                                         f"Sub-agent {agent_id[:8]} appears stalled. Check on it.")
                        last_injection[agent_id] = now

        except Exception as e:
            logging.error(f"Swarm monitor error: {e}")

        time.sleep(1)

if __name__ == "__main__":
    main()
