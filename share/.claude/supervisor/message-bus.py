#!/usr/bin/env python3
"""
Layer AH — Inter-agent message bus server.

Unix domain socket server. Agents connect via helper script to:
  - Broadcast status updates to all listeners
  - Send targeted messages to specific agent sessions
  - Query agent status

Undelivered messages are persisted to disk queues for pickup
by UserPromptSubmit hook on next turn.

Handles stale socket files on restart.
"""
import json
import os
import socket
import sys
import threading
import time
import logging

SUPERVISOR_DIR = os.path.expanduser("~/.claude/supervisor")
SOCKET_PATH = os.path.join(SUPERVISOR_DIR, "message-bus.sock")
CONFIG_PATH = os.path.join(SUPERVISOR_DIR, "config.json")
LOG_PATH = os.path.join(SUPERVISOR_DIR, "message-bus.log")
MESSAGES_DIR = os.path.join(SUPERVISOR_DIR, "messages")

logging.basicConfig(filename=LOG_PATH, level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")

clients: dict = {}  # session_id -> connection
clients_lock = threading.Lock()

def persist_message(to_session_id, from_agent, message):
    """Write to per-session queue file for pickup by UserPromptSubmit."""
    os.makedirs(MESSAGES_DIR, exist_ok=True)
    queue_path = os.path.join(MESSAGES_DIR, f"{to_session_id}.queue")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "from_agent": from_agent, "message": message})
    try:
        with open(queue_path, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

def handle_client(conn, addr):
    """Handle a single client connection."""
    session_id = None
    try:
        data = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
            try:
                msg = json.loads(data.decode())
                data = b""
                msg_type = msg.get("type", "")
                from_session = msg.get("from_session", "unknown")
                from_agent = msg.get("from_agent", from_session)

                if msg_type == "register":
                    session_id = from_session
                    with clients_lock:
                        clients[session_id] = conn
                    logging.info(f"Client registered: {session_id[:8]}")
                    conn.send(json.dumps({"status": "registered"}).encode())

                elif msg_type == "broadcast":
                    message = msg.get("message", "")
                    with clients_lock:
                        dead = []
                        for sid, c in clients.items():
                            if sid != from_session:
                                try:
                                    c.send(json.dumps({"from": from_agent, "msg": message}).encode())
                                except Exception:
                                    dead.append(sid)
                                    persist_message(sid, from_agent, message)
                        for sid in dead:
                            del clients[sid]

                elif msg_type == "send":
                    to_session = msg.get("to_session", "")
                    message = msg.get("message", "")
                    with clients_lock:
                        target = clients.get(to_session)
                    if target:
                        try:
                            target.send(json.dumps({"from": from_agent, "msg": message}).encode())
                        except Exception:
                            persist_message(to_session, from_agent, message)
                    else:
                        persist_message(to_session, from_agent, message)

                elif msg_type == "ping":
                    conn.send(json.dumps({"status": "pong"}).encode())

            except json.JSONDecodeError:
                pass  # Accumulate more data
    except Exception as e:
        logging.error(f"Client error: {e}")
    finally:
        if session_id:
            with clients_lock:
                clients.pop(session_id, None)
        try:
            conn.close()
        except Exception:
            pass

def cleanup_stale_socket():
    """Remove stale socket file if server isn't running."""
    if os.path.exists(SOCKET_PATH):
        try:
            test = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            test.connect(SOCKET_PATH)
            test.close()
            # Connection succeeded — another server is running
            logging.error("Another message bus is already running. Exiting.")
            sys.exit(0)
        except ConnectionRefusedError:
            os.remove(SOCKET_PATH)
        except Exception:
            try:
                os.remove(SOCKET_PATH)
            except Exception:
                pass

def main():
    logging.info("Message bus started")
    os.makedirs(SUPERVISOR_DIR, exist_ok=True)
    cleanup_stale_socket()

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(SOCKET_PATH)
    os.chmod(SOCKET_PATH, 0o600)
    server.listen(50)
    server.settimeout(1.0)

    logging.info(f"Listening on {SOCKET_PATH}")
    while True:
        try:
            conn, addr = server.accept()
            t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
            t.start()
        except socket.timeout:
            pass
        except Exception as e:
            logging.error(f"Server error: {e}")

if __name__ == "__main__":
    main()
