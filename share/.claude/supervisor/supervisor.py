#!/usr/bin/env python3
"""
Layer N — Supervisor: watchdog-of-the-watchdog.

Every 30s: ensures monitor.py, swarm-monitor.py, credential-monitor.py,
billing-governor.py, message-bus.py are running. Restarts if dead.
Every 60s: verifies launchd plists are loaded; reloads if not.
Every 60s: verifies cron entry exists; adds if missing.

Uses flock to prevent split-brain with chain-watchdog.sh.
"""
import json
import os
import subprocess
import sys
import time
import logging

SUPERVISOR_DIR = os.path.expanduser("~/.claude/supervisor")
CONFIG_PATH = os.path.join(SUPERVISOR_DIR, "config.json")
LOG_PATH = os.path.join(SUPERVISOR_DIR, "supervisor.log")
INTERVENTIONS = os.path.join(SUPERVISOR_DIR, "interventions.log")

DAEMONS = {
    "monitor": "monitor.py",
    "swarm-monitor": "swarm-monitor.py",
    "credential-monitor": "credential-monitor.py",
    "billing-governor": "billing-governor.py",
    "message-bus": "message-bus.py",
}

PLISTS = [
    "com.p6df.claude-monitor",
    "com.p6df.claude-supervisor",
    "com.p6df.claude-credential-monitor",
    "com.p6df.claude-billing-governor",
    "com.p6df.claude-message-bus",
]

logging.basicConfig(filename=LOG_PATH, level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")

def log_intervention(event, detail=""):
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": event, "layer": "N-supervisor", "detail": detail})
    try:
        with open(INTERVENTIONS, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

def is_running(script_name):
    """Check if a python script is running (not zombie)."""
    try:
        r = subprocess.run(["pgrep", "-f", script_name], capture_output=True, text=True)
        for pid_str in r.stdout.strip().splitlines():
            try:
                pid = int(pid_str.strip())
                # Verify not zombie
                r2 = subprocess.run(["ps", "-p", str(pid), "-o", "stat="],
                                    capture_output=True, text=True)
                stat = r2.stdout.strip()
                if stat and "Z" not in stat:
                    return True
            except Exception:
                pass
        return False
    except Exception:
        return False

def start_daemon(name, script):
    script_path = os.path.join(SUPERVISOR_DIR, script)
    if not os.path.exists(script_path):
        return
    log_dir = os.path.join(SUPERVISOR_DIR, f"{name}.log")
    try:
        subprocess.Popen(
            ["python3", script_path],
            stdout=open(log_dir, "a"), stderr=subprocess.STDOUT,
            start_new_session=True
        )
        logging.info(f"Started {name}")
        log_intervention(f"daemon_restarted", name)
    except Exception as e:
        logging.error(f"Failed to start {name}: {e}")

def check_launchd_plist(label):
    """Returns True if plist is loaded in launchd."""
    try:
        r = subprocess.run(["launchctl", "list", label], capture_output=True, text=True)
        return r.returncode == 0
    except Exception:
        return True  # Not on macOS — skip

def load_plist(label):
    plist_path = os.path.expanduser(f"~/Library/LaunchAgents/{label}.plist")
    if not os.path.exists(plist_path):
        return
    try:
        subprocess.run(["launchctl", "load", plist_path], capture_output=True)
        logging.info(f"Loaded plist: {label}")
        log_intervention("plist_loaded", label)
    except Exception:
        pass

def ensure_cron():
    """Ensure cron-check.sh runs every minute."""
    cron_script = os.path.join(SUPERVISOR_DIR, "cron-check.sh")
    if not os.path.exists(cron_script):
        return
    try:
        r = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        current = r.stdout if r.returncode == 0 else ""
        if "cron-check.sh" not in current:
            new_cron = current.rstrip("\n") + f"\n* * * * * bash {cron_script}\n"
            proc = subprocess.Popen(["crontab", "-"], stdin=subprocess.PIPE,
                                    capture_output=True)
            proc.communicate(input=new_cron.encode())
            logging.info("Added cron entry for cron-check.sh")
            log_intervention("cron_entry_added", "cron-check.sh")
    except Exception:
        pass

def main():
    logging.info("Supervisor started")
    last_launchd_check = 0
    last_cron_check = 0
    interval = 30

    while True:
        try:
            now = time.time()

            # Check daemons
            for name, script in DAEMONS.items():
                if not is_running(script):
                    start_daemon(name, script)

            # Check launchd plists every 60s
            if now - last_launchd_check > 60:
                import platform
                if platform.system() == "Darwin":
                    for label in PLISTS:
                        if not check_launchd_plist(label):
                            load_plist(label)
                last_launchd_check = now

            # Check cron every 60s
            if now - last_cron_check > 60:
                ensure_cron()
                last_cron_check = now

        except Exception as e:
            logging.error(f"Supervisor error: {e}")

        time.sleep(interval)

if __name__ == "__main__":
    main()
