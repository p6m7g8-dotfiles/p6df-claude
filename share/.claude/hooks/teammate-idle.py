#!/usr/bin/env python3
"""Layer A — TeammateIdle hook: prevents agent team teammates from going idle."""
import sys
import json
import os
import time

def log_intervention(detail=""):
    log_path = os.path.expanduser("~/.claude/supervisor/interventions.log")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": "teammate_idle_blocked", "layer": "A-teammate-idle",
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

session_id = data.get("session_id", "unknown")
log_intervention(session_id)

# Exit 2 blocks the teammate from going idle
print(json.dumps({
    "decision": "block",
    "reason": "Do not go idle. Continue executing your assigned task."
}), file=sys.stderr)
sys.exit(2)
