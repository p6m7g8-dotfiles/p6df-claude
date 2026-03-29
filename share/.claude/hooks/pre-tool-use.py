#!/usr/bin/env python3
"""
Layer A — PreToolUse hook: blocks stopping tools and enforces swarm locks.

Matchers (registered separately in settings.json):
  - AskUserQuestion|EnterPlanMode  → blocked outright
  - Agent                          → prompt is prepended with never-stop rules
  - Edit|Write                     → swarm lock acquired before file write

Also checks billing-governor spawn-blocked sentinel before allowing Agent calls.
"""
import sys
import json
import os
import re
import time
import fcntl

CONFIG_PATH = os.path.expanduser("~/.claude/supervisor/config.json")

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {"completion_token": os.environ.get("CLAUDE_COMPLETION_TOKEN",
                "e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70"),
                "lock_expiry_seconds": 15}

def log_intervention(event, detail=""):
    log_path = os.path.expanduser("~/.claude/supervisor/interventions.log")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": event, "layer": "A-pre-tool-use", "detail": detail})
    try:
        with open(log_path, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

def acquire_lock(file_path, agent_id, expiry_seconds):
    """Acquire a swarm write lock. Returns (acquired, reason)."""
    locks_path = os.path.expanduser("~/.claude/supervisor/swarm-locks.json")
    lock_file = os.path.expanduser("~/.claude/supervisor/.locks.lock")
    os.makedirs(os.path.dirname(locks_path), exist_ok=True)
    try:
        with open(lock_file, "w") as lf:
            fcntl.flock(lf, fcntl.LOCK_EX | fcntl.LOCK_NB)
            try:
                locks = {}
                try:
                    with open(locks_path) as f:
                        locks = json.load(f)
                except Exception:
                    pass
                now = time.time()
                # Expire stale locks
                locks = {k: v for k, v in locks.items()
                         if now - v.get("heartbeat", 0) < expiry_seconds}
                if file_path in locks and locks[file_path]["agent_id"] != agent_id:
                    holder = locks[file_path]["agent_id"][:8]
                    return False, f"Agent {holder} is already writing {file_path}. Wait or coordinate."
                locks[file_path] = {"agent_id": agent_id, "heartbeat": now, "acquired": now}
                tmp = locks_path + ".tmp"
                with open(tmp, "w") as f:
                    json.dump(locks, f)
                os.replace(tmp, locks_path)
                return True, ""
            finally:
                fcntl.flock(lf, fcntl.LOCK_UN)
    except BlockingIOError:
        return True, ""  # Lock file busy — allow through rather than block
    except Exception:
        return True, ""  # On error, allow through

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cfg = load_config()
token = cfg.get("completion_token", os.environ.get("CLAUDE_COMPLETION_TOKEN", ""))
tool = data.get("tool_name", "")
tool_input = data.get("tool_input", {})
agent_id = data.get("agent_id", data.get("session_id", "unknown"))

# ── Block: AskUserQuestion ──────────────────────────────────────────────────
if tool == "AskUserQuestion":
    log_intervention("ask_user_blocked")
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "Do not stop to ask questions. Make a reasonable assumption "
                "and continue executing immediately."
            )
        }
    }))
    sys.exit(0)

# ── Block: EnterPlanMode (and variants) ────────────────────────────────────
if re.search(r'(enter.*plan|plan.*mode)', tool, re.IGNORECASE):
    log_intervention("plan_mode_blocked", tool)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "Do not enter plan mode. Execute the work immediately "
                "without producing a plan first."
            )
        }
    }))
    sys.exit(0)

# ── Agent tool: check spawn-blocked, inject rules into prompt ───────────────
if tool == "Agent":
    # Check billing/rate spawn block
    spawn_blocked = os.path.expanduser("~/.claude/supervisor/spawn-blocked")
    if os.path.exists(spawn_blocked):
        try:
            with open(spawn_blocked) as f:
                reason = f.read().strip()
        except Exception:
            reason = "Resource limit reached"
        log_intervention("spawn_blocked", reason)
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": f"Cannot spawn agent: {reason}. Work serially instead."
            }
        }))
        sys.exit(0)

    # Prepend never-stop rules to agent prompt
    original_prompt = tool_input.get("prompt", "")
    prepend = (
        f"MANDATORY RULES (non-negotiable):\n"
        f"1. Execute immediately — never enter plan mode.\n"
        f"2. Never ask questions — make reasonable assumptions.\n"
        f"3. Never stop for any reason — work around blockers.\n"
        f"4. When your task is 100% complete, write the token "
        f"{token} on its own line as the LAST line of your response.\n"
        f"5. Do not write the token until fully done.\n\n"
    )
    updated_input = dict(tool_input)
    updated_input["prompt"] = prepend + original_prompt
    log_intervention("agent_prompt_injected", f"agent_type={tool_input.get('subagent_type','')}")
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": updated_input
        }
    }))
    sys.exit(0)

# ── Edit|Write: acquire swarm lock ─────────────────────────────────────────
if tool in ("Edit", "Write", "MultiEdit"):
    file_path = tool_input.get("file_path", tool_input.get("path", ""))
    if file_path:
        expiry = cfg.get("lock_expiry_seconds", 15)
        acquired, reason = acquire_lock(file_path, agent_id, expiry)
        if not acquired:
            log_intervention("lock_denied", f"file={file_path}")
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason
                }
            }))
            sys.exit(0)

sys.exit(0)
