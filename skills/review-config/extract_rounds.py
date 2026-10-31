"""Write every round of the main sessions since a time: the hand-back and the user's reply.

Usage: python3 -I extract_rounds.py SINCE_EPOCH_S OUT_DIR

One Markdown file per project folder in ~/.claude/projects. A round is the
assistant's last text before a message typed by the user, and that message.
Messages injected by hooks, skills, compaction and subagents are skipped.
"""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
HANDBACK_CHARS = 3500
REPLY_CHARS = 700
PASTE_CHARS = 300
INJECTED_PREFIXES = (
    "<task-notification", "<artifact-content", "This session is being continued",
    "Base directory", "[Request interrupted", "<local-command", "<command-",
    "Stop hook feedback", "Skill /", "(Re-invocation", "Another Claude",
    "<agent-message", "[Image",
)


def typed_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(p.get("text", "") for p in content
                        if isinstance(p, dict) and p.get("type") == "text")
    return ""


def cleaned(text: str) -> str:
    text = re.sub(r"<system-reminder>.*?</system-reminder>", "", text, flags=re.S)
    text = re.sub(r"<ide_[a-z_]+>.*?</ide_[a-z_]+>", "[ide]", text, flags=re.S)
    text = re.sub(r"(<pasted_content[^>]*>)(.*?)(</pasted_content[^>]*>)",
                  lambda m: m.group(1) + m.group(2)[:PASTE_CHARS] + "..." + m.group(3),
                  text, flags=re.S)
    return text.strip()


def rounds(transcript: Path, since_iso: str):
    handback = ""
    for line in transcript.open(errors="replace"):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("isSidechain"):
            continue
        content = entry.get("message", {}).get("content")
        if entry.get("type") == "assistant" and isinstance(content, list):
            for part in content:
                if part.get("type") == "text" and part["text"].strip():
                    handback = part["text"]
                elif part.get("type") == "tool_use" and part["name"] == "AskUserQuestion":
                    handback += "\n[AskUserQuestion] " + json.dumps(part["input"])[:1200]
        elif entry.get("type") == "user":
            reply = cleaned(typed_text(content))
            if not reply or reply.startswith(INJECTED_PREFIXES):
                continue
            stamp = entry.get("timestamp", "")
            if stamp >= since_iso:
                yield stamp, handback[:HANDBACK_CHARS], reply[:REPLY_CHARS]
            handback = ""


def main():
    since_s, out_dir = float(sys.argv[1]), Path(sys.argv[2])
    since_iso = datetime.fromtimestamp(since_s, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    out_dir.mkdir(parents=True, exist_ok=True)
    for project in sorted(p for p in PROJECTS.iterdir() if p.is_dir()):
        blocks = []
        for transcript in sorted(project.glob("*.jsonl")):
            if transcript.stat().st_mtime < since_s:
                continue
            for stamp, handback, reply in rounds(transcript, since_iso):
                blocks.append(f"=== #{len(blocks) + 1} {stamp[:16]}\n--- HANDBACK:\n{handback}\n"
                              f"--- USER REPLY:\n{reply}\n")
        if blocks:
            home_prefix = "-" + str(Path.home()).strip("/").replace("/", "-")
            name = project.name.removeprefix(home_prefix).strip("-") or "home"
            out = out_dir / f"{name}.md"
            out.write_text("\n".join(blocks))
            print(f"{out}: {len(blocks)} rounds")


if __name__ == "__main__":
    main()
