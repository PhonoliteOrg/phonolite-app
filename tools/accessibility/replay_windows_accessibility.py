"""Convert bounded Windows accessibility logs into native AXTree replay input."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys


PREFIX = "Windows accessibility update "
PROJECT = pathlib.Path(__file__).resolve().parents[2]


def read_sessions(log: pathlib.Path) -> dict[str, list[dict]]:
    sessions: dict[str, list[dict]] = {}
    for line_number, line in enumerate(log.read_text(encoding="utf-8-sig").splitlines(), 1):
        if PREFIX not in line:
            continue
        payload = line.split(PREFIX, 1)[1]
        # AppLogger escapes backslashes and line breaks when persisting messages.
        if re.match(r"^\[[^]]+\]\[[A-Z]+\] ", line):
            payload = re.sub(r"\\([\\rn])", lambda match: {"r": "\r", "n": "\n", "\\": "\\"}[match[1]], payload)
        try:
            update = json.loads(payload)
        except json.JSONDecodeError as error:
            raise ValueError(f"Invalid accessibility JSON at line {line_number}: {error}") from error
        if not isinstance(update, dict) or not isinstance(update.get("session"), str):
            raise ValueError(f"Missing string session ID at line {line_number}")
        if type(update.get("batch")) is not int or update["batch"] < 1 or not isinstance(update.get("nodes"), list):
            raise ValueError(f"Invalid batch metadata at line {line_number}")
        for node in update["nodes"]:
            if not isinstance(node, dict) or type(node.get("id")) is not int or node["id"] < 0:
                raise ValueError(f"Invalid node ID at line {line_number}")
            children = node.get("children")
            if not isinstance(children, list) or any(type(child) is not int or child < 0 for child in children):
                raise ValueError(f"Invalid child IDs at line {line_number}")
        sessions.setdefault(update["session"], []).append(update)
    return sessions


def session_error(updates: list[dict]) -> str | None:
    for expected, update in enumerate(updates, 1):
        if update["batch"] != expected:
            return f"expected batch {expected}, found {update['batch']}"
    return None


def replay_text(updates: list[dict]) -> str:
    lines = ["R"]
    for update in updates:
        lines.append(f"B {len(update['nodes'])}")
        for node in update["nodes"]:
            children = node["children"]
            lines.append(" ".join(map(str, [node["id"], len(children), *children])))
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=pathlib.Path, help="Phonolite debug.log or a console log containing the capture prefix")
    parser.add_argument("--session", help="Select a session explicitly; by default use the latest complete sequence")
    parser.add_argument("--output", type=pathlib.Path, default=PROJECT / "build/accessibility/windows_startup.trace")
    parser.add_argument("--native-executable", type=pathlib.Path, help="Run the headless native AXTree replayer after conversion")
    args = parser.parse_args()
    try:
        sessions = read_sessions(args.log)
        if not sessions:
            raise ValueError(f"No '{PREFIX.strip()}' entries found")
        if args.session:
            if args.session not in sessions:
                raise ValueError(f"Session {args.session!r} is absent from the log")
            selected = args.session
            error = session_error(sessions[selected])
            if error:
                raise ValueError(f"Selected session is incomplete or out of order: {error}")
        else:
            selected = None
            for session, updates in reversed(sessions.items()):
                error = session_error(updates)
                if error:
                    print(f"Skipping incomplete session {session}: {error}", file=sys.stderr)
                else:
                    selected = session
                    break
            if selected is None:
                raise ValueError("No complete sequence from batch 1 remains; capture a fresh launch")
        updates = sessions[selected]
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(replay_text(updates), encoding="ascii")
        print(f"Converted session {selected}: {len(updates)} batches -> {args.output}")
        if args.native_executable:
            return subprocess.run([str(args.native_executable.resolve()), str(args.output.resolve())], check=False).returncode
        print("Conversion only; use --native-executable to validate against the native accessibility tree.")
        return 0
    except (OSError, ValueError) as error:
        print(f"Accessibility replay failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
