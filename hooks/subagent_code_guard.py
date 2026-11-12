"""Decides whether a subagent's tool call may run: it may change no code and no documentation.

Reads a PreToolUse payload from a subagent on stdin. Prints a refusal for the
hook and exits 0, or prints nothing to let the call run. Code and documentation
are the files git would track, git state, Claude's memory, and files outside
both a repository and a temporary folder.
"""

import itertools
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile


class UnknownPath(Exception):
    """A write target that cannot be resolved without running the command."""


REMOTE = "<remote>"


HOME = os.path.expanduser("~")
TEMP_DIR = tempfile.gettempdir()
TEMP_ROOTS = {os.path.realpath(root) for root in (TEMP_DIR, "/tmp", "/private/tmp", "/dev")}
MEMORY = re.compile(re.escape(os.path.realpath(os.path.join(HOME, ".claude", "projects"))) + r"/[^/]+/memory(/|$)")

SEPARATORS = {";", "&", "&&", "|", "||", "|&", ";;", "(", ")"}
PREFIX_WORDS = {"!", "{", "}", "then", "do", "else", "elif", "if", "while", "until", "time"}
WRAPPERS = {"sudo", "env", "nice", "nohup", "timeout", "exec", "command", "stdbuf", "caffeinate"}
WRAPPER_OPTIONS_WITH_VALUE = {"-u", "-g", "-h", "-p", "-C", "-U", "-n", "-s", "-k", "-S", "-i", "-o", "-e"}
XARGS_OPTIONS_WITH_VALUE = {"-n", "-I", "-J", "-L", "-P", "-s", "-d", "-E", "-a", "-R", "-S"}

ALL_ARGUMENTS = {"rm", "rmdir", "unlink", "touch", "mkdir", "truncate", "shred", "tee", "mv"}
ARGUMENTS_AFTER_FIRST = {"chmod", "chown", "chgrp"}
LAST_ARGUMENT = {"cp", "ln", "install", "rsync", "ditto", "scp"}
PACKAGE_MANAGERS = {"npm", "pnpm", "yarn", "bun", "cargo", "poetry", "uv"}
PACKAGE_CHANGES = {"install", "i", "add", "remove", "rm", "uninstall", "update", "upgrade", "ci", "init", "lock"}
FORMATTERS = {"black", "isort", "swiftformat", "rustfmt", "autoflake"}
FORMATTER_READ_FLAGS = {"--check", "--diff", "--lint", "--dryrun", "--dry-run"}
FIX_FLAGS = {"--fix", "--fix-only", "--write", "--in-place"}

GIT_WRITES = {
    "add", "commit", "push", "pull", "fetch", "reset", "checkout", "switch", "restore", "rebase",
    "merge", "cherry-pick", "revert", "apply", "am", "clean", "rm", "mv", "init", "clone",
    "update-ref", "gc", "prune", "repack", "bisect", "filter-branch", "replace", "sparse-checkout",
    "maintenance",
}
GIT_SUBCOMMAND_WRITES = {
    "worktree": {"add", "remove", "move", "prune", "lock", "unlock", "repair"},
    "remote": {"add", "remove", "rm", "rename", "set-url", "set-head", "set-branches", "prune", "update"},
    "notes": {"add", "append", "copy", "edit", "merge", "prune", "remove"},
    "submodule": {"add", "update", "init", "deinit", "sync", "absorbgitdirs", "set-branch", "set-url"},
}
GIT_LIST_FLAGS = {"-l", "--list", "-a", "--all", "-r", "--remotes", "-v", "-vv", "--contains",
                  "--no-contains", "--merged", "--no-merged", "--points-at", "--show-current", "-n"}
GIT_BRANCH_WRITE_FLAGS = {"-d", "-D", "-m", "-M", "-c", "-C", "-f", "--force", "--delete", "--move",
                          "--copy", "-u", "--set-upstream-to", "--unset-upstream", "--edit-description"}
GIT_CONFIG_WRITES = {"set", "unset", "edit", "rename-section", "remove-section", "--unset",
                     "--unset-all", "--add", "--replace-all", "--edit", "-e", "--rename-section",
                     "--remove-section"}


def refusal(what):
    return json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"A subagent changes no code and no documentation, and this call {what}. Report the "
            "change you would make, with file and line, and the main session makes it. Files in "
            f"the temporary folder ({TEMP_DIR}) and files git ignores may be written; a command "
            "refused by mistake can be rewritten with literal paths."),
    }})


def enclosing_work_tree(path):
    directory = path
    while True:
        if os.path.exists(os.path.join(directory, ".git")):
            return directory
        parent = os.path.dirname(directory)
        if parent == directory:
            return None
        directory = parent


def is_protected(path):
    """Whether writing to path changes code or documentation."""
    real = os.path.realpath(path)
    if MEMORY.match(real):
        return True
    if any(real == root or real.startswith(root + os.sep) for root in TEMP_ROOTS):
        return False
    top = enclosing_work_tree(real)
    if top is None:
        return True
    relative = os.path.relpath(real, top)
    if relative == "." or relative.split(os.sep)[0] == ".git":
        return True
    ignored = subprocess.run(["git", "-C", top, "check-ignore", "-q", "--", relative],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return ignored.returncode != 0


def resolve(word, cwd, temp_variables):
    """Returns the absolute path a shell word names, or raises UnknownPath."""
    word = re.sub(r"^~(?=/|$)", HOME, word)

    def expand(match):
        name = match.group(1) or match.group(2)
        known = {"HOME": HOME, "TMPDIR": TEMP_DIR, "PWD": cwd, **temp_variables}
        if name not in known or known[name] is None:
            raise UnknownPath(word)
        return known[name]

    word = re.sub(r"\$\{(\w+)\}|\$(\w+)", expand, word)
    if "$" in word or "`" in word or cwd is None and not word.startswith("/"):
        raise UnknownPath(word)
    return os.path.normpath(os.path.join(cwd or "/", word))


def shell_lines(command):
    """Yields the command with heredoc bodies removed and unquoted newlines as separators."""
    out, quote, i, heredocs = [], None, 0, []
    while i < len(command):
        char = command[i]
        if quote:
            if char == "\\" and quote == '"' and i + 1 < len(command):
                out.append(command[i:i + 2])
                i += 2
                continue
            if char == quote:
                quote = None
            out.append(char)
        elif char == "\\" and i + 1 < len(command):
            out.append(command[i:i + 2] if command[i + 1] != "\n" else " ")
            i += 2
            continue
        elif char in "'\"":
            quote = char
            out.append(char)
        elif command.startswith("<<", i) and not command.startswith("<<<", i):
            match = re.match(r"<<(-?)[ \t]*(['\"]?)(\w+)\2", command[i:])
            if match:
                heredocs.append(match.group(3))
                i += match.end()
                continue
            out.append(char)
        elif char == "\n":
            out.append(" ; ")
            if heredocs:
                lines = command[i + 1:].split("\n")
                skipped = 0
                while lines and heredocs:
                    line = lines.pop(0)
                    skipped += len(line) + 1
                    if line.strip() == heredocs[0]:
                        heredocs.pop(0)
                i += skipped
        elif char == "#" and (i == 0 or command[i - 1] in " \t\n;&|("):
            end = command.find("\n", i)
            i = len(command) if end < 0 else end
            continue
        elif char == "`":
            out.append(" ; ")
        else:
            out.append(char)
        i += 1
    if quote:
        raise ValueError("unbalanced quote")
    return "".join(out)


def simple_commands(command):
    """Yields (words, redirection targets) for each simple command."""
    lexer = shlex.shlex(shell_lines(command), posix=True, punctuation_chars=";&|()<>")
    lexer.whitespace_split = True
    lexer.commenters = ""
    words, targets, tokens = [], [], list(lexer)
    i = 0
    while i < len(tokens):
        token = tokens[i]
        is_punctuation = token and all(c in ";&|()<>" for c in token)
        if is_punctuation and ">" in token:
            if words and words[-1].isdigit():
                words.pop()
            if token.endswith("("):
                yield words, targets
                words, targets = [], []
            elif i + 1 < len(tokens):
                following = tokens[i + 1]
                if not (token.endswith("&") and (following.isdigit() or following == "-")):
                    targets.append(following)
                i += 1
        elif is_punctuation and token.endswith("("):
            yield words, targets
            words, targets = [], []
        elif is_punctuation and "<" in token:
            i += 1
        elif is_punctuation:
            yield words, targets
            words, targets = [], []
        else:
            words.append(token)
        i += 1
    yield words, targets


def strip_prefix(words):
    """Returns the words from the command word on, and whether xargs feeds it."""
    fed_by_xargs = False
    while words:
        word = words[0]
        if word in PREFIX_WORDS or re.match(r"^\w+=", word):
            words = words[1:]
        elif os.path.basename(word.lstrip("\\")) in WRAPPERS | {"xargs"}:
            name = os.path.basename(word.lstrip("\\"))
            fed_by_xargs = fed_by_xargs or name == "xargs"
            with_value = XARGS_OPTIONS_WITH_VALUE if name == "xargs" else WRAPPER_OPTIONS_WITH_VALUE
            words = words[1:]
            while words and (words[0].startswith("-") or re.match(r"^\w+=", words[0])):
                words = words[2:] if words[0] in with_value else words[1:]
            if name == "timeout" and words:
                words = words[1:]
        else:
            break
    return words, fed_by_xargs


def positional(arguments):
    return [a for a in arguments if not a.startswith("-") or a == "-"]


def git_write(arguments, cwd):
    """Returns the repository a writing git command changes, or None for a read."""
    repository, i = cwd, 0
    while i < len(arguments) and arguments[i].startswith("-"):
        if arguments[i] in {"-C", "--git-dir", "--work-tree"} and i + 1 < len(arguments):
            repository = os.path.join(cwd or "/", arguments[i + 1]) if cwd or arguments[i + 1].startswith("/") else None
            i += 2
        elif arguments[i] in {"-c", "--namespace", "--config-env"}:
            i += 2
        else:
            i += 1
    if i == len(arguments):
        return None
    subcommand, rest = arguments[i], arguments[i + 1:]
    places = positional(rest)
    writes = (
        subcommand in GIT_WRITES
        or subcommand == "stash" and (not rest or rest[0] not in {"list", "show"})
        or subcommand in GIT_SUBCOMMAND_WRITES and bool(rest) and rest[0] in GIT_SUBCOMMAND_WRITES[subcommand]
        or subcommand == "tag" and not set(rest) & GIT_LIST_FLAGS and (bool(places) or bool(set(rest) & {"-d", "-a", "-s", "-f", "-m"}))
        or subcommand == "branch" and (bool(set(rest) & GIT_BRANCH_WRITE_FLAGS) or bool(places) and not set(rest) & GIT_LIST_FLAGS)
        or subcommand == "config" and (bool(set(rest) & GIT_CONFIG_WRITES) or len(places) >= 2 and not any(a.startswith("--get") for a in rest))
    )
    if not writes:
        return None
    if subcommand == "clone" and len(places) < 2:
        return repository if repository is not None else ""
    if subcommand in {"clone", "init"} and places:
        return os.path.join(repository or "/", places[-1]) if repository or places[-1].startswith("/") else ""
    return repository if repository is not None else ""


def write_targets(words, cwd):
    """Returns the paths a simple command writes; '' stands for one it cannot name."""
    name = os.path.basename(words[0].lstrip("\\"))
    arguments = words[1:]
    places = positional(arguments)
    if name in ALL_ARGUMENTS:
        return places
    if name in ARGUMENTS_AFTER_FIRST:
        return places[1:]
    if name in LAST_ARGUMENT:
        if "-t" in arguments and arguments.index("-t") + 1 < len(arguments):
            return [arguments[arguments.index("-t") + 1]]
        return places[-1:]
    if name == "dd":
        return [a[3:] for a in arguments if a.startswith("of=")]
    if name == "sed" and any(a == "--in-place" or a.startswith("--in-place=") or re.fullmatch(r"-[nrEsuz]*i.*", a) for a in arguments):
        return in_place_files(arguments, {"-e", "--expression", "-f", "--file"})
    if name == "perl" and any(re.fullmatch(r"-[a-hj-z]*i.*", a) for a in arguments):
        return in_place_files(arguments, {"-e", "-E"})
    if name == "patch":
        return ["."]
    if name == "curl":
        return downloads(arguments, "o", "O", {"-o", "--output"}, {"-O", "--remote-name", "--remote-name-all"})
    if name == "wget":
        to_stdout = any(a.endswith("O-") or a == "--output-document=-" for a in arguments) or any(
            a in {"-O", "--output-document"} and b == "-" for a, b in zip(arguments, arguments[1:]))
        if to_stdout:
            return []
        return downloads(arguments, "O", None, {"-O", "--output-document"}, set()) or ["."]
    if name == "git":
        repository = git_write(arguments, cwd)
        return [] if repository is None else [repository]
    if name in PACKAGE_MANAGERS and places and places[0] in PACKAGE_CHANGES:
        return ["."]
    if name == "gh" and len(places) >= 2 and (places[0], places[1]) in {("pr", "merge"), ("repo", "sync"), ("repo", "delete")}:
        return [REMOTE]
    rewrites = (set(arguments) & FIX_FLAGS
                or name in FORMATTERS and not set(arguments) & FORMATTER_READ_FLAGS
                or name in {"gofmt", "clang-format", "autopep8"} and bool(set(arguments) & {"-w", "-i", "--in-place"})
                or name == "ruff" and places[:1] == ["format"] and not set(arguments) & FORMATTER_READ_FLAGS)
    if rewrites:
        files = [p for p in places if p not in {"check", "format"}]
        return files or ["."]
    return []


def in_place_files(arguments, script_options):
    files, script_given, i = [], False, 0
    while i < len(arguments):
        argument = arguments[i]
        if argument in script_options:
            script_given, i = True, i + 2
            continue
        if argument and not argument.startswith("-"):
            files.append(argument)
        i += 1
    return files if script_given else files[1:]


def downloads(arguments, value_flag, remote_flag, value_options, remote_options):
    targets = []
    for i, argument in enumerate(arguments):
        takes_value = argument in value_options or re.fullmatch(rf"-[a-zA-Z]*{value_flag}", argument)
        if takes_value and i + 1 < len(arguments) and arguments[i + 1] != "-":
            targets.append(arguments[i + 1])
        elif argument in remote_options or remote_flag and re.fullmatch(rf"-[a-zA-Z]*{remote_flag}[a-zA-Z]*", argument):
            targets.append(".")
    return targets


def shell_verdict(command, cwd):
    """Returns why a shell command changes code or documentation, or None."""
    temp_variables = {}
    for match in re.finditer(r"\b(\w+)=[\"']?(\$\(mktemp\b|\$TMPDIR|\$\{TMPDIR\}|/tmp/|/private/tmp/)", command):
        temp_variables[match.group(1)] = os.path.join(TEMP_DIR, "assigned")
    try:
        commands = list(simple_commands(command))
    except ValueError:
        return "cannot be read by the hook (unbalanced quotes)"
    for words, redirections in commands:
        words, fed_by_xargs = strip_prefix(words)
        targets = list(redirections)
        if words:
            name = os.path.basename(words[0].lstrip("\\"))
            if name in {"cd", "pushd"}:
                destination = positional(words[1:])
                try:
                    cwd = HOME if not destination else resolve(destination[0], cwd, temp_variables)
                except UnknownPath:
                    cwd = None
                continue
            if name == "find":
                paths = list(itertools.takewhile(lambda w: not w.startswith(("-", "(", "!")), words[1:])) or ["."]
                if "-delete" in words:
                    targets += paths
                for marker in ("-exec", "-execdir", "-ok"):
                    if marker in words:
                        inner = words[words.index(marker) + 1:]
                        inner = inner[:inner.index(";")] if ";" in inner else [w for w in inner if w != "+"]
                        if inner and write_targets([w if w != "{}" else paths[0] for w in inner], cwd):
                            targets += paths
            else:
                targets += write_targets(words, cwd)
                if fed_by_xargs and name in ALL_ARGUMENTS | ARGUMENTS_AFTER_FIRST:
                    targets.append("")
        for target in targets:
            if target == REMOTE:
                return "changes code on the remote repository"
            try:
                path = resolve(target, cwd, temp_variables) if target else None
            except UnknownPath:
                path = None
            if path is None:
                return f"writes to a place the hook cannot resolve ({' '.join(words[:3]) or target})"
            if is_protected(path):
                return f"writes {path}"
    return None


def main():
    call = json.load(sys.stdin)
    if not call.get("agent_id"):
        return
    tool_name = call.get("tool_name", "")
    tool_input = call.get("tool_input") or {}
    cwd = call.get("cwd") or None
    if tool_name in {"EnterWorktree", "ExitWorktree"}:
        print(refusal("changes the repository's worktrees"))
    elif tool_name in {"Edit", "Write", "NotebookEdit"}:
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        if not path or is_protected(os.path.join(cwd or "/", path)):
            print(refusal(f"writes {path}"))
    elif tool_name == "Bash":
        reason = shell_verdict(tool_input.get("command", ""), cwd)
        if reason:
            print(refusal(reason))


if __name__ == "__main__":
    main()
