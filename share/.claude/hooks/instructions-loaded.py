#!/usr/bin/env python3
"""
Layer A9 — InstructionsLoaded hook: verifies CLAUDE.md contains our rules.

When CLAUDE.md loads, checks that the completion token is present. If not,
injects the requirement as additionalContext (belt-and-suspenders for F layer).
Cannot block (InstructionsLoaded exit code is ignored per docs).
"""
import sys
import json
import os

CONFIG_PATH = os.path.expanduser("~/.claude/supervisor/config.json")

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {"completion_token": os.environ.get("CLAUDE_COMPLETION_TOKEN",
                "e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70")}

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cfg = load_config()
token = cfg.get("completion_token", os.environ.get("CLAUDE_COMPLETION_TOKEN", ""))

# The loaded instructions content may or may not be in the hook input
# Inject as additionalContext regardless as a safety net
print(json.dumps({
    "additionalContext": (
        f"INSTRUCTIONS LOADED. Reminder: when your task is fully complete, "
        f"write the token {token} on its own line as the last line of your response."
    )
}))
sys.exit(0)
