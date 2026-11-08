"""Write every round of the main sessions since a time: the hand-back, its page and the reply.

Usage: python3 -I extract_rounds.py SINCE_EPOCH_S OUT_DIR

One Markdown file per project folder in ~/.claude/projects. A round is the
assistant's last text before a message typed by the user, the text of the
round's page, the round's interruptions, rejected tool calls and forced checks,
and that message. The page is the scratchpad HTML file the hand-back names (the
last written or edited, if it names several), as the Write and Edit calls so far
left it, else the last one written or edited in the round. An unreadable,
negative or future SINCE_EPOCH_S counts as 0.
Messages injected by hooks, skills, compaction and subagents are skipped.
"""

import html
import json
import re
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
HANDBACK_CHARS = 3500
PAGE_CHARS = 15000
REPLY_CHARS = 700
PASTE_CHARS = 300
INJECTED_PREFIXES = (
    "<task-notification", "<artifact-content", "This session is being continued",
    "Base directory", "[Request interrupted", "<local-command", "<command-",
    "Stop hook feedback", "Skill /", "(Re-invocation", "Another Claude",
    "<agent-message", "[Image",
)
EVENT_PREFIXES = {
    "[Request interrupted": "interrupted",
    "Stop hook feedback": "check forced",
}
REJECTED_PREFIX = "The user doesn't want to proceed"


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


def tool_results(content) -> list:
    if not isinstance(content, list):
        return []
    texts = []
    for part in content:
        if isinstance(part, dict) and part.get("type") == "tool_result":
            result = part.get("content")
            if isinstance(result, list):
                result = " ".join(p.get("text", "") for p in result if isinstance(p, dict))
            texts.append(str(result or ""))
    return texts


def page_text(markup: str) -> str:
    markup = re.sub(r"<(style|script)\b.*?</\1>", "", markup, flags=re.S | re.I)
    markup = re.sub(r"<(?:tr|p|h[1-6]|li|div|label)\b", "\n\\g<0>", markup, flags=re.I)
    markup = re.sub(r"<[^>]+>", " ", markup)
    lines = (re.sub(r"[ \t]+", " ", line).strip() for line in html.unescape(markup).splitlines())
    return "\n".join(line for line in lines if line)


def is_page(path: str) -> bool:
    return path.endswith(".html") and "/scratchpad/" in path


def rounds(transcript: Path, since_iso: str):
    handback = round_page = ""
    pages = {}
    events = Counter()
    after_rejection = False
    for line in transcript.open(errors="replace"):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("isSidechain"):
            continue
        content = entry.get("message", {}).get("content")
        if entry.get("type") == "assistant":
            after_rejection = False
        if entry.get("type") == "assistant" and isinstance(content, list):
            for part in content:
                if part.get("type") == "text" and part["text"].strip():
                    handback = part["text"]
                elif part.get("type") == "tool_use" and part["name"] == "AskUserQuestion":
                    handback += "\n[AskUserQuestion] " + json.dumps(part["input"])[:1200]
                elif part.get("type") == "tool_use" and part["name"] in ("Write", "Edit"):
                    tool_input = part["input"]
                    path = str(tool_input.get("file_path", ""))
                    if part["name"] == "Write" and is_page(path):
                        pages.pop(path, None)
                        pages[path] = str(tool_input.get("content", ""))
                        round_page = path
                    elif part["name"] == "Edit" and path in pages:
                        old, new = str(tool_input.get("old_string", "")), str(tool_input.get("new_string", ""))
                        pages[path] = pages.pop(path).replace(old, new, -1 if tool_input.get("replace_all") else 1)
                        round_page = path
        elif entry.get("type") == "user":
            rejected = sum(t.startswith(REJECTED_PREFIX) for t in tool_results(content))
            events["action rejected"] += rejected
            reply = cleaned(typed_text(content))
            for prefix, event in EVENT_PREFIXES.items():
                if reply.startswith(prefix) and not (event == "interrupted" and (after_rejection or rejected)):
                    events[event] += 1
            after_rejection = rejected > 0
            if not reply or reply.startswith(INJECTED_PREFIXES):
                continue
            stamp = entry.get("timestamp", "")
            if stamp >= since_iso:
                summary = ", ".join(f"{name} {count}" for name, count in sorted(events.items()) if count)
                named = [path for path in pages if path in handback]
                page = page_text(pages.get(named[-1] if named else round_page, ""))
                yield stamp, handback[:HANDBACK_CHARS], page[:PAGE_CHARS], summary, reply[:REPLY_CHARS]
            handback = round_page = ""
            events.clear()


def main():
    try:
        since_s = float(sys.argv[1])
    except ValueError:
        since_s = 0.0
    if not 0 <= since_s <= time.time():
        since_s = 0.0
    out_dir = Path(sys.argv[2])
    since_iso = datetime.fromtimestamp(since_s, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    out_dir.mkdir(parents=True, exist_ok=True)
    for project in sorted(p for p in PROJECTS.iterdir() if p.is_dir()):
        blocks = []
        for transcript in sorted(project.glob("*.jsonl")):
            if transcript.stat().st_mtime < since_s:
                continue
            for stamp, handback, page, events, reply in rounds(transcript, since_iso):
                page_block = f"--- PAGE:\n{page}\n" if page else ""
                events_block = f"--- EVENTS: {events}\n" if events else ""
                blocks.append(f"=== #{len(blocks) + 1} {stamp[:16]}\n--- HANDBACK:\n{handback}\n"
                              f"{page_block}{events_block}--- USER REPLY:\n{reply}\n")
        if blocks:
            home_prefix = "-" + str(Path.home()).strip("/").replace("/", "-")
            name = project.name.removeprefix(home_prefix).strip("-") or "home"
            out = out_dir / f"{name}.md"
            out.write_text("\n".join(blocks))
            print(f"{out}: {len(blocks)} rounds")


if __name__ == "__main__":
    main()
