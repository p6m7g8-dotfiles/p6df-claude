#!/usr/bin/env python3
"""
Layer Z — Swarm billing governor daemon.

Tracks cumulative token consumption across all active agents by monitoring
transcript JSONL files. When approaching budget threshold, writes spawn-blocked
sentinel (checked by pre-tool-use.py Agent hook) and injects warning into
root coordinator. Clears sentinel when agents complete.

Also handles rate-limit coordination (Layer AE): schedules retries with jitter.
"""
import json
import os
import random
import subprocess
import sys
import time
import logging

SUPERVISOR_DIR = os.path.expanduser("~/.claude/supervisor")
REGISTRY_PATH = os.path.join(SUPERVISOR_DIR, "swarm-registry.json")
CONFIG_PATH = os.path.join(SUPERVISOR_DIR, "config.json")
LOG_PATH = os.path.join(SUPERVISOR_DIR, "billing-governor.log")
INTERVENTIONS = os.path.join(SUPERVISOR_DIR, "interventions.log")
SPAWN_BLOCKED = os.path.join(SUPERVISOR_DIR, "spawn-blocked")
BILLING_SENTINEL = os.path.join(SUPERVISOR_DIR, "billing-blocked")

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

def estimate_tokens_from_transcript(transcript_path):
    """Rough token estimate: chars / 4."""
    try:
        size = os.path.getsize(transcript_path)
        return size // 4
    except Exception:
        return 0

def total_swarm_tokens(registry):
    total = 0
    for swarm_id, swarm in registry.get("swarms", {}).items():
        root = swarm.get("root", {})
        if root.get("transcript_path"):
            total += estimate_tokens_from_transcript(root["transcript_path"])
        for agent_info in swarm.get("agents", {}).values():
            if agent_info.get("transcript_path"):
                total += estimate_tokens_from_transcript(agent_info["transcript_path"])
    return total

def inject_warning(registry, message):
    """Inject warning into root coordinator of each active swarm."""
    for swarm_id, swarm in registry.get("swarms", {}).items():
        root = swarm.get("root", {})
        pane = root.get("tmux_pane", "")
        if pane:
            try:
                subprocess.run(["tmux", "send-keys", "-t", pane,
                                f"WARNING: {message}", "Enter"],
                               capture_output=True, timeout=5)
            except Exception:
                pass

def log_intervention(event, detail=""):
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": event, "layer": "Z-billing-governor", "detail": detail})
    try:
        with open(INTERVENTIONS, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

def main():
    logging.info("Billing governor started")

    while True:
        try:
            cfg = load_config()
            budget_pct = cfg.get("spawn_budget_pct", 80)
            rate_limits = cfg.get("rate_limits", {})
            rpm_limit = rate_limits.get("requests_per_minute", 60)
            tpm_limit = rate_limits.get("tokens_per_minute", 100000)

            registry = load_registry()
            total_tokens = total_swarm_tokens(registry)

            # Billing is blocked by stop-failure hook — propagate to spawn block
            if os.path.exists(BILLING_SENTINEL):
                if not os.path.exists(SPAWN_BLOCKED):
                    with open(SPAWN_BLOCKED, "w") as f:
                        f.write("Billing suspended. Work serially — do not spawn agents.")
                    log_intervention("spawn_blocked_billing")
                    inject_warning(registry, "Billing suspended. Do not spawn new agents.")
            else:
                # Clear spawn block if billing recovered
                if os.path.exists(SPAWN_BLOCKED):
                    try:
                        with open(SPAWN_BLOCKED) as f:
                            reason = f.read()
                        if "Billing" in reason:
                            os.remove(SPAWN_BLOCKED)
                            log_intervention("spawn_unblocked")
                    except Exception:
                        pass

            # Token budget warning
            estimated_budget = tpm_limit * budget_pct / 100
            active_agents = sum(
                1 + len(s.get("agents", {}))
                for s in registry.get("swarms", {}).values()
            )
            if active_agents > 0:
                per_agent_tokens = total_tokens / max(active_agents, 1)
                if per_agent_tokens > estimated_budget:
                    if not os.path.exists(SPAWN_BLOCKED):
                        with open(SPAWN_BLOCKED, "w") as f:
                            f.write(f"Token budget {budget_pct}% reached. Work serially.")
                        log_intervention("spawn_blocked_tokens", f"tokens={total_tokens}")
                        inject_warning(registry,
                                       "Token budget approaching limit. Do not spawn new agents. Work serially.")

        except Exception as e:
            logging.error(f"Billing governor error: {e}")

        time.sleep(10)

if __name__ == "__main__":
    main()
