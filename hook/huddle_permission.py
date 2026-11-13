#!/usr/bin/env python3
import json
import os
import signal
import sys
import time
import uuid

BASE = os.path.expanduser("~/.claude/huddle")
PENDING = os.path.join(BASE, "pending")
RESPONSES = os.path.join(BASE, "responses")
HEARTBEAT = os.path.join(BASE, "app.heartbeat")
WAIT_SECONDS = 590
HEARTBEAT_MAX_AGE = 6


def app_alive():
    try:
        return time.time() - os.path.getmtime(HEARTBEAT) < HEARTBEAT_MAX_AGE
    except OSError:
        return False


def write_atomic(path, payload):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f)
    os.replace(tmp, path)


def remove(*paths):
    for p in paths:
        try:
            os.remove(p)
        except OSError:
            pass


class TranscriptWatch:
    def __init__(self, path, tool_name, tool_input):
        self.path = path
        self.tool_name = tool_name
        self.tool_input = tool_input
        self.candidates = set()
        self.offset = 0
        try:
            self.offset = max(0, os.path.getsize(path) - 2_000_000)
        except OSError:
            self.path = None
            return
        self.scan()

    def entries(self):
        with open(self.path, "rb") as f:
            f.seek(self.offset)
            chunk = f.read()
        end = chunk.rfind(b"\n") + 1
        self.offset += end
        for raw in chunk[:end].split(b"\n"):
            if b'"tool_use' not in raw:
                continue
            try:
                entry = json.loads(raw)
            except ValueError:
                continue
            content = (entry.get("message") or {}).get("content")
            if isinstance(content, list):
                yield from (block for block in content if isinstance(block, dict))

    def scan(self):
        resolved = False
        for block in self.entries():
            if block.get("type") == "tool_use" and block.get("name") == self.tool_name \
                    and block.get("input") == self.tool_input:
                self.candidates.add(block.get("id"))
            elif block.get("type") == "tool_result" and block.get("tool_use_id") in self.candidates:
                self.candidates.discard(block.get("tool_use_id"))
                resolved = True
        return resolved

    def resolved_elsewhere(self):
        if not self.path:
            return False
        try:
            return self.scan()
        except OSError:
            return False


def main():
    data = json.load(sys.stdin)
    if not app_alive():
        return

    os.makedirs(PENDING, exist_ok=True)
    os.makedirs(RESPONSES, exist_ok=True)
    request_id = uuid.uuid4().hex
    pending_path = os.path.join(PENDING, request_id + ".json")
    response_path = os.path.join(RESPONSES, request_id + ".json")

    def cleanup(*_):
        remove(pending_path, response_path)
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    write_atomic(pending_path, {
        "id": request_id,
        "sessionId": data.get("session_id"),
        "cwd": data.get("cwd"),
        "toolName": data.get("tool_name"),
        "toolInput": data.get("tool_input") or {},
        "createdAt": time.time(),
        "hookPid": os.getpid(),
    })

    watch = TranscriptWatch(data.get("transcript_path") or "", data.get("tool_name"), data.get("tool_input") or {})
    next_transcript_check = time.time() + 1

    response = None
    deadline = time.time() + WAIT_SECONDS
    try:
        while time.time() < deadline:
            if time.time() >= next_transcript_check:
                if watch.resolved_elsewhere():
                    break
                next_transcript_check = time.time() + 1
            if os.path.exists(response_path):
                with open(response_path) as f:
                    response = json.load(f)
                break
            if not app_alive():
                break
            time.sleep(0.2)
    finally:
        remove(pending_path, response_path)

    if not response or response.get("behavior") not in ("allow", "deny"):
        return

    decision = {"behavior": response["behavior"]}
    if response["behavior"] == "allow" and response.get("updatedInput") is not None:
        decision["updatedInput"] = response["updatedInput"]
    if response["behavior"] == "deny":
        decision["message"] = response.get("message") or "The user denied this in Agent Huddle."
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}))


if __name__ == "__main__":
    main()
