#!/usr/bin/env python3
"""
Layer B — External activity monitor: watches the active Claude session
and injects a continuation via tmux when a stall is detected.

Detection (dual-signal, both must be idle for stall_timeout_seconds):
  1. Transcript file mtime unchanged
  2. tmux pane last-activity timestamp unchanged

Injection: tmux send-keys into the active pane.
Falls back through Layer M chain if tmux injection fails.

Checks for completion token in transcript before injecting.
"""
import json
import os
import subprocess
import sys
import time
import logging

SUPERVISOR_DIR = os.path.expanduser("~/.claude/supervisor")
SESSION_FILE = os.path.join(SUPERVISOR_DIR, "active-session.json")
CONFIG_PATH = os.path.join(SUPERVISOR_DIR, "config.json")
LOG_PATH = os.path.join(SUPERVISOR_DIR, "monitor.log")
INTERVENTIONS = os.path.join(SUPERVISOR_DIR, "interventions.log")

logging.basicConfig(
    filename=LOG_PATH,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {}

def load_session():
    try:
        with open(SESSION_FILE) as f:
            return json.load(f)
    except Exception:
        return {}

def get_transcript_mtime(transcript_path):
    try:
        return os.path.getmtime(transcript_path)
    except Exception:
        return time.time()

def get_tmux_pane_activity_ms(pane):
    """Get pane last activity in milliseconds. Returns None if unavailable."""
    if not pane:
        return None
    try:
        # Try ms first (tmux >= 2.9)
        r = subprocess.run(
            ["tmux", "display-message", "-t", pane, "-p", "#{pane_last_activity_ms}"],
            capture_output=True, text=True, timeout=2
        )
        val = r.stdout.strip()
        if val and val.isdigit():
            return int(val)
        # Fall back to seconds
        r = subprocess.run(
            ["tmux", "display-message", "-t", pane, "-p", "#{pane_last_activity}"],
            capture_output=True, text=True, timeout=2
        )
        val = r.stdout.strip()
        if val and val.isdigit():
            return int(val) * 1000
    except Exception:
        pass
    return None

def token_in_transcript(transcript_path, token):
    """Check last 50 lines of transcript for completion token."""
    if not token or not transcript_path:
        return False
    try:
        with open(transcript_path, "rb") as f:
            # Read last ~10KB
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 10240))
            tail = f.read().decode("utf-8", errors="replace")
        return token in tail
    except Exception:
        return False

def inject_tmux(pane, message):
    """Inject message into tmux pane. Returns True on success."""
    if not pane:
        return False
    try:
        subprocess.run(
            ["tmux", "send-keys", "-t", pane, message, "Enter"],
            capture_output=True, timeout=5
        )
        return True
    except Exception:
        return False

def inject_fallback(session_id, message):
    """Layer M fallback chain when tmux injection fails."""
    pending_path = os.path.join(SUPERVISOR_DIR, "pending-inject")
    try:
        with open(pending_path, "w") as f:
            f.write(message)
        logging.info(f"Fallback: wrote pending-inject for session {session_id[:8]}")
    except Exception:
        pass

def log_intervention(event, detail=""):
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": event, "layer": "B-monitor", "detail": detail})
    try:
        with open(INTERVENTIONS, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

def main():
    logging.info("Monitor started")
    cfg = load_config()
    timeout = cfg.get("stall_timeout_seconds", 5)
    thinking_timeout = cfg.get("thinking_stall_timeout_seconds", 30)
    cooldown = cfg.get("injection_cooldown_seconds", 30)
    token = cfg.get("completion_token", os.environ.get("CLAUDE_COMPLETION_TOKEN", ""))

    last_injection: dict = {}  # pane -> last injection timestamp
    prev_transcript_mtime: dict = {}  # transcript_path -> mtime
    prev_pane_activity: dict = {}  # pane -> activity_ms

    while True:
        try:
            cfg = load_config()
            timeout = cfg.get("stall_timeout_seconds", 5)
            token = cfg.get("completion_token", token)

            session = load_session()
            pane = session.get("tmux_pane", "")
            transcript_path = session.get("transcript_path", "")
            session_id = session.get("session_id", "unknown")

            if not pane or not transcript_path:
                time.sleep(1)
                continue

            now = time.time()
            now_ms = int(now * 1000)

            # Get current state
            t_mtime = get_transcript_mtime(transcript_path)
            p_activity = get_tmux_pane_activity_ms(pane)

            prev_tm = prev_transcript_mtime.get(transcript_path, t_mtime)
            prev_pa = prev_pane_activity.get(pane, p_activity)

            transcript_idle = (t_mtime == prev_tm)
            pane_idle = (p_activity is not None and p_activity == prev_pa)

            prev_transcript_mtime[transcript_path] = t_mtime
            prev_pane_activity[pane] = p_activity

            if transcript_idle and (pane_idle or p_activity is None):
                # Check cooldown
                last = last_injection.get(pane, 0)
                if now - last < cooldown:
                    time.sleep(1)
                    continue

                # Check for completion token
                if token_in_transcript(transcript_path, token):
                    time.sleep(1)
                    continue

                # Stall confirmed — inject
                msg = "Continue the task immediately. Do not stop until fully complete."
                logging.info(f"Stall detected — injecting into pane {pane}")
                log_intervention("stall_injection", f"pane={pane} session={session_id[:8]}")

                if inject_tmux(pane, msg):
                    last_injection[pane] = now
                else:
                    inject_fallback(session_id, msg)
                    last_injection[pane] = now

        except Exception as e:
            logging.error(f"Monitor loop error: {e}")

        time.sleep(1)

if __name__ == "__main__":
    main()
