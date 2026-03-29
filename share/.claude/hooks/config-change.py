#!/usr/bin/env python3
"""
Layer P — ConfigChange hook: blocks settings changes that would remove hook registrations.

Matches user_settings and local_settings changes. Verifies the new settings
still contain our critical hook event registrations before allowing through.
"""
import sys
import json
import os
import time

REQUIRED_HOOKS = {"Stop", "SubagentStop", "PreToolUse", "UserPromptSubmit", "SessionStart"}

def log_intervention(detail=""):
    log_path = os.path.expanduser("~/.claude/supervisor/interventions.log")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": "config_change_checked", "layer": "P-config-change",
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

config_source = data.get("config_source", "")
new_config = data.get("new_config", {})

# Only enforce on user and local settings (policy_settings cannot be blocked)
if config_source not in ("user_settings", "local_settings"):
    sys.exit(0)

# Check if new config removes our hooks
if "hooks" in new_config:
    registered = set(new_config["hooks"].keys())
    missing = REQUIRED_HOOKS - registered
    if missing:
        log_intervention(f"blocked: missing hooks {missing}")
        print(json.dumps({
            "decision": "block",
            "reason": (
                f"This settings change would remove required hook registrations: {missing}. "
                f"Change rejected. Edit the hooks section to preserve resilience hooks."
            )
        }))
        sys.exit(2)

log_intervention(f"allowed: source={config_source}")
sys.exit(0)
