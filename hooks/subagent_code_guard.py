"""Decides whether a subagent's tool call may run: it may change no code and no documentation.

Reads a PreToolUse payload from a subagent on stdin. Prints a refusal for the
hook and exits 0, or prints nothing to let the call run. is_protected defines
what counts as code and documentation.
"""

import collections
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile


class UnknownPath(Exception):
    """A write target that cannot be named without running the command."""


class Refused(Exception):
    """A call that changes code or documentation; the message says how."""


HOME = os.path.expanduser("~")
CLAUDE_HOME = os.path.realpath(os.path.join(HOME, ".claude"))
TEMP_DIR = tempfile.gettempdir()
TEMPORARY_ROOTS = {os.path.realpath(root) for root in (TEMP_DIR, "/tmp", "/private/tmp")}
DEVICE_ROOT = "/dev"
CONFIGURATION_FILE = re.compile(r"^(CLAUDE.*\.md|AGENTS\.md)$")

PUNCTUATION = ";&|()<>"
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
PREFIX_WORDS = {"!", "{", "}", "then", "do", "else", "elif", "if", "while", "until", "coproc"}
WRAPPER_OPTIONS_WITH_VALUE = {
    "sudo": {"-u", "-g", "-h", "-p", "-C", "-U", "-D", "-R", "-T", "-r", "-t"},
    "env": {"-u", "-C", "--unset", "--chdir"},
    "nice": {"-n", "--adjustment"},
    "timeout": {"-s", "-k", "--signal", "--kill-after"},
    "xargs": {"-n", "-I", "-J", "-L", "-P", "-s", "-d", "-E", "-a", "-R", "-S"},
    "stdbuf": {"-i", "-o", "-e"},
    "caffeinate": {"-t", "-w"},
    "time": {"-o", "-f"},
    "exec": {"-a"},
    "nohup": set(),
    "command": set(),
}
WATCH_OPTIONS_WITH_VALUE = {"-n", "--interval", "-d", "--differences"}

ALL_ARGUMENTS = {"rm", "rmdir", "unlink", "touch", "mkdir", "truncate", "shred", "tee", "mv", "ln"}
ARGUMENTS_AFTER_FIRST = {"chmod", "chown", "chgrp"}
LAST_ARGUMENT = {"cp", "install", "rsync", "ditto", "scp"}
COMPRESSORS = {"gzip", "gunzip", "bzip2", "bunzip2", "xz", "unxz", "zstd", "unzstd", "lz4",
               "compress", "uncompress"}
PACKAGE_TOOLS = {"npm", "pnpm", "yarn", "bun", "cargo", "poetry", "uv", "go"}
PACKAGE_CHANGES = {"install", "i", "add", "remove", "rm", "uninstall", "update", "upgrade", "ci",
                   "init", "lock", "fmt", "fix", "new", "generate", "get", "mod", "vendor"}
FORMATTERS = {"black", "isort", "swiftformat", "rustfmt", "autoflake"}
FORMATTER_READ_FLAGS = {"--check", "--diff", "--lint", "--dryrun", "--dry-run"}
FIX_FLAGS = {"--fix", "--fix-only", "--write", "--in-place"}
FIND_EXEC = ("-exec", "-execdir", "-ok", "-okdir")
FIND_FILE_OUTPUT = {"-fprint", "-fprint0", "-fls", "-fprintf"}

GIT_READS = {
    "status", "log", "diff", "show", "blame", "annotate", "grep", "ls-files", "ls-tree",
    "ls-remote", "rev-parse", "rev-list", "cat-file", "describe", "shortlog", "for-each-ref",
    "show-ref", "show-branch", "merge-base", "check-ignore", "check-attr", "check-ref-format",
    "name-rev", "whatchanged", "diff-tree", "diff-files", "diff-index", "range-diff", "cherry",
    "count-objects", "verify-commit", "verify-tag", "help", "version", "var", "fsck",
}
GIT_SUBCOMMAND_WRITES = {
    "worktree": {"add", "remove", "move", "prune", "lock", "unlock", "repair"},
    "remote": {"add", "remove", "rm", "rename", "set-url", "set-head", "set-branches", "prune", "update"},
    "notes": {"add", "append", "copy", "edit", "merge", "prune", "remove"},
    "submodule": {"add", "update", "init", "deinit", "sync", "absorbgitdirs", "set-branch", "set-url"},
    "reflog": {"expire", "delete"},
}
GIT_LIST_FLAGS = {"-l", "--list", "-a", "--all", "-r", "--remotes", "-v", "-vv", "--contains",
                  "--no-contains", "--merged", "--no-merged", "--points-at", "--show-current", "-n"}
GIT_BRANCH_WRITE_FLAGS = {"-d", "-D", "-m", "-M", "-c", "-C", "-f", "--force", "--delete", "--move",
                          "--copy", "-u", "--set-upstream-to", "--unset-upstream", "--edit-description"}
GIT_CONFIG_WRITES = {"set", "unset", "edit", "rename-section", "remove-section", "--unset",
                     "--unset-all", "--add", "--replace-all", "--edit", "-e", "--rename-section",
                     "--remove-section"}
GH_REMOTE_CODE_CHANGES = {("pr", "merge"), ("repo", "sync"), ("repo", "delete"),
                          ("release", "create"), ("release", "delete")}
GH_API_OPTIONS_WITH_VALUE = {"-X", "--method", "-f", "-F", "--field", "--raw-field", "--input", "-H",
                             "--header", "-q", "--jq", "-t", "--template", "--hostname", "--cache", "-p",
                             "--preview"}
GH_API_CODE_ENDPOINT = re.compile(r"repos/[^/]+/[^/]+/(contents|git/|merges|pulls/\d+/merge|branches/)")


def refusal(what):
    return json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"A subagent changes no code and no documentation, and this call {what}. Report the "
            "change you would make, with file and line, and the main session makes it. Files in "
            f"the temporary folder ({TEMP_DIR}) and build output that git ignores may be written; "
            "a command refused by mistake can be rewritten with literal paths."),
    }})


def within(path, folder):
    return path == folder or path.startswith(folder.rstrip(os.sep) + os.sep)


def enclosing_work_tree(path):
    directory = path
    while True:
        if os.path.exists(os.path.join(directory, ".git")):
            return directory
        parent = os.path.dirname(directory)
        if parent == directory:
            return None
        directory = parent


def git_output(top, *arguments):
    return subprocess.run(["git", "-C", top, *arguments], stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, text=True)


def is_protected(path):
    """Whether writing to path changes code or documentation.

    Protected are Claude's configuration folder and everything around it, every
    `.claude` folder and CLAUDE or AGENTS file, every file git would track, a
    folder holding any of these, and everything outside both a repository and
    the temporary folders.
    """
    real = os.path.realpath(path)
    if within(real, CLAUDE_HOME) or within(CLAUDE_HOME, real):
        return True
    if any(within(real, root) for root in TEMPORARY_ROOTS) or within(real, DEVICE_ROOT):
        return False
    if ".claude" in real.split(os.sep) or CONFIGURATION_FILE.match(os.path.basename(real)):
        return True
    top = enclosing_work_tree(real)
    if top is None:
        return True
    relative = os.path.relpath(real, top)
    if relative == "." or relative.split(os.sep)[0] == ".git":
        return True
    if git_output(top, "check-ignore", "-q", "--", relative).returncode != 0:
        return True
    return os.path.isdir(real) and holds_protected(real, top, relative)


def holds_protected(directory, top, relative):
    """Whether an ignored folder holds a tracked file, a repository or Claude's files."""
    if git_output(top, "ls-files", "--", relative).stdout.strip():
        return True
    for _, folders, files in os.walk(directory):
        if ".git" in folders or ".claude" in folders or ".git" in files:
            return True
        if any(CONFIGURATION_FILE.match(name) for name in files):
            return True
    return False


def known_variables(command):
    """Returns the variables whose value the hook can name, None for one it cannot."""
    assignments = re.findall(r"(?<![\w-])(\w+)=([\"']?)([^\s;&|\"')]*)", command)
    counts = collections.Counter(name for name, _, _ in assignments)
    known = {"HOME": HOME, "TMPDIR": TEMP_DIR}
    for name, _, value in assignments:
        if name in known:
            known[name] = None
    temporary_value = r"(\$\(mktemp\b|/tmp/|/private/tmp/" + (r"|\$TMPDIR\b|\$\{TMPDIR\})" if known["TMPDIR"] else ")")
    for name, _, value in assignments:
        if counts[name] == 1 and ".." not in value and re.match(temporary_value, value):
            known[name] = os.path.join(TEMP_DIR, "assigned")
    return known


def resolve(word, cwd, variables):
    """Returns the absolute path a shell word names in cwd, or raises UnknownPath."""
    if not word:
        raise UnknownPath(word)
    word = re.sub(r"^~(?=/|$)", HOME, word)

    def expand(match):
        name = match.group(1) or match.group(2)
        value = cwd if name == "PWD" and "PWD" not in variables else variables.get(name)
        if value is None:
            raise UnknownPath(word)
        return value

    word = re.sub(r"\$\{(\w+)\}|\$(\w+)", expand, word)
    if "$" in word or "`" in word or cwd is None and not word.startswith("/"):
        raise UnknownPath(word)
    return os.path.normpath(os.path.join(cwd or "/", word))


def shell_text(command):
    """Returns the command with heredoc bodies and comments removed, and unquoted newlines as separators."""
    out, quote, i, heredocs, word_start = [], None, 0, [], True
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
        elif char == "\\":
            if i + 1 == len(command):
                raise ValueError("trailing backslash")
            out.append(command[i:i + 2] if command[i + 1] != "\n" else " ")
            word_start = command[i + 1] == "\n"
            i += 2
            continue
        elif char in "'\"":
            quote = char
            out.append(char)
        elif command.startswith("((", i) or command.startswith("$((", i):
            end = command.find("))", i)
            if end < 0:
                raise ValueError("unbalanced arithmetic")
            out.append(re.sub(r"[<>]", " ", command[i:end + 2]))
            i = end + 2
            word_start = False
            continue
        elif command.startswith("<<", i) and not command.startswith("<<<", i):
            match = re.match(r"<<(-?)[ \t]*(['\"]?)(\w+)\2", command[i:])
            if match:
                heredocs.append(match.group(3))
                i += match.end()
                continue
            out.append(char)
        elif char == "#" and word_start:
            end = command.find("\n", i)
            i = len(command) if end < 0 else end
            continue
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
        elif char == "`":
            out.append(" ; ")
        else:
            out.append(char)
        word_start = quote is None and char in " \t\n;&|(`"
        i += 1
    if quote:
        raise ValueError("unbalanced quote")
    return "".join(out)


def simple_commands(command):
    """Yields (words, redirection targets, separator after it) for each simple command."""
    lexer = shlex.shlex(shell_text(command), posix=True, punctuation_chars=PUNCTUATION)
    lexer.whitespace_split = True
    lexer.commenters = ""
    tokens = list(lexer)
    words, targets, i = [], [], 0
    while i < len(tokens):
        token = tokens[i]
        is_punctuation = bool(token) and all(c in PUNCTUATION for c in token)
        if is_punctuation and token.endswith("("):
            yield words, targets, "("
            words, targets = [], []
        elif is_punctuation and ">" in token:
            if words and words[-1].isdigit():
                words.pop()
            following = tokens[i + 1] if i + 1 < len(tokens) else ""
            if following and all(c in PUNCTUATION for c in following):
                targets.append("")
            else:
                if not (token.endswith("&") and (following.isdigit() or following == "-")):
                    targets.append(following)
                i += 1
        elif is_punctuation and "<" in token:
            i += 1
        elif is_punctuation:
            yield words, targets, token
            words, targets = [], []
        else:
            words.append(token)
        i += 1
    yield words, targets, None


def strip_prefix(words):
    """Returns the words from the command word on, and whether xargs feeds it."""
    fed_by_xargs = False
    while words:
        name = os.path.basename(words[0])
        if words[0] in PREFIX_WORDS or re.match(r"^\w+=", words[0]):
            words = words[1:]
        elif name in WRAPPER_OPTIONS_WITH_VALUE:
            fed_by_xargs = fed_by_xargs or name == "xargs"
            with_value = WRAPPER_OPTIONS_WITH_VALUE[name]
            words = words[1:]
            while words and (words[0].startswith("-") or name == "env" and re.match(r"^\w+=", words[0])):
                if name == "env" and words[0] in {"-S", "--split-string"} and len(words) > 1:
                    words = shlex.split(words[1]) + words[2:]
                    break
                words = words[2:] if words[0] in with_value else words[1:]
            if name == "timeout" and words:
                words = words[1:]
        else:
            break
    return words, fed_by_xargs


def positional(arguments):
    return [a for a in arguments if not a.startswith("-") or a == "-"]


def git_writes(subcommand, rest):
    places = positional(rest)
    flags = set(rest)
    if subcommand in GIT_READS:
        return False
    if subcommand in GIT_SUBCOMMAND_WRITES:
        return bool(rest) and rest[0] in GIT_SUBCOMMAND_WRITES[subcommand]
    if subcommand == "stash":
        return not rest or rest[0] not in {"list", "show"}
    if subcommand == "tag":
        return not flags & GIT_LIST_FLAGS and (bool(places) or bool(flags & {"-d", "-a", "-s", "-f", "-m"}))
    if subcommand == "branch":
        writes = any(a == f or a.startswith(f + "=") for a in rest for f in GIT_BRANCH_WRITE_FLAGS)
        return writes or bool(places) and not flags & GIT_LIST_FLAGS
    if subcommand == "config":
        return bool(flags & GIT_CONFIG_WRITES) or len(places) >= 2 and not any(a.startswith("--get") for a in rest)
    return True


def git_targets(arguments, git_environment):
    """Returns the (kind, word) targets of a git command; kind is 'repository' or 'path'."""
    locations, i = [], 0
    while i < len(arguments) and arguments[i].startswith("-"):
        argument = arguments[i]
        if argument in {"-C", "--git-dir", "--work-tree"} and i + 1 < len(arguments):
            locations.append(arguments[i + 1])
            i += 2
        elif argument.startswith(("--git-dir=", "--work-tree=")):
            locations.append(argument.split("=", 1)[1])
            i += 1
        elif argument in {"-c", "--namespace", "--config-env"}:
            i += 2
        else:
            i += 1
    if i >= len(arguments):
        return []
    subcommand, rest = arguments[i], arguments[i + 1:]
    if not git_writes(subcommand, rest):
        return []
    if subcommand == "push":
        raise Refused("pushes to a remote repository")
    base = locations[0] if locations else "."
    places = positional(rest)
    if subcommand == "clone":
        if len(places) > 1:
            name = places[1]
        else:
            name = re.sub(r"\.git$", "", os.path.basename(places[0].rstrip("/"))) if places else ""
        return [("path", os.path.join(base, name) if name else "")]
    if subcommand == "init":
        return [("path", os.path.join(base, places[0]) if places else base)]
    return [("repository", location) for location in (locations or ["."]) + git_environment]


def gh_change(places, arguments):
    if tuple(places[:2]) in GH_REMOTE_CODE_CHANGES:
        return True
    if places[:1] != ["api"]:
        return False
    endpoint, i, rest = None, 0, arguments[arguments.index("api") + 1:]
    while i < len(rest) and endpoint is None:
        if rest[i] in GH_API_OPTIONS_WITH_VALUE:
            i += 2
            continue
        if not rest[i].startswith("-"):
            endpoint = rest[i]
        i += 1
    method = None
    for i, argument in enumerate(arguments):
        if argument in {"-X", "--method"} and i + 1 < len(arguments):
            method = arguments[i + 1].upper()
        elif argument.startswith("--method="):
            method = argument.split("=", 1)[1].upper()
        elif argument.startswith("-X") and len(argument) > 2:
            method = argument[2:].upper()
    if method is None and set(arguments) & {"-f", "-F", "--field", "--raw-field", "--input"}:
        method = "POST"
    return method in {"PUT", "POST", "PATCH", "DELETE"} and bool(GH_API_CODE_ENDPOINT.search(endpoint or ""))


def tar_targets(arguments):
    letters, archive, directory = set(), None, None
    for i, argument in enumerate(arguments):
        following = arguments[i + 1] if i + 1 < len(arguments) else None
        if argument in {"--extract", "--get"}:
            letters.add("x")
        elif argument in {"--create", "--append", "--update"}:
            letters.add("c")
        elif argument.startswith("--file="):
            archive = argument.split("=", 1)[1]
        elif argument.startswith("--directory="):
            directory = argument.split("=", 1)[1]
        elif argument == "--file":
            archive = following
        elif argument in {"--directory", "-C"}:
            directory = following
        elif argument.startswith("-") or i == 0:
            cluster = argument.lstrip("-")
            letters |= set(cluster)
            if cluster.endswith("f"):
                archive = following
    targets = [directory or "."] if "x" in letters else []
    if letters & {"c", "r", "u", "A"} and archive and archive != "-":
        targets.append(archive)
    return targets


def in_place_files(arguments, script_options):
    files, script_given, i = [], False, 0
    while i < len(arguments):
        argument = arguments[i]
        if argument in script_options:
            script_given, i = True, i + 2
            continue
        if argument and not argument.startswith("-") and argument != "inplace":
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


def path_targets(name, arguments):
    """Returns the words a command other than git writes to; '' stands for one it cannot name."""
    places = positional(arguments)
    flags = set(arguments)
    if name in ALL_ARGUMENTS:
        return places
    if name in ARGUMENTS_AFTER_FIRST:
        return places if any(a.startswith("--reference") for a in arguments) else places[1:]
    if name in LAST_ARGUMENT:
        if "-t" in arguments[:-1]:
            return [arguments[arguments.index("-t") + 1]]
        return places[-1:]
    if name == "dd":
        return [a[3:] for a in arguments if a.startswith("of=")]
    if name in COMPRESSORS:
        keeps = flags & {"--stdout", "--keep", "--list", "--test"} or any(
            re.fullmatch(r"-[a-zA-Z0-9]*[cklt][a-zA-Z0-9]*", a) for a in arguments)
        return [] if keeps else places
    if name == "tar":
        return tar_targets(arguments)
    if name == "unzip":
        if flags & {"-l", "-t", "-p", "-Z", "-v"}:
            return []
        return [arguments[arguments.index("-d") + 1]] if "-d" in arguments[:-1] else ["."]
    if name == "sed" and any(a == "--in-place" or a.startswith("--in-place=") or re.fullmatch(r"-[nrEsuz]*i.*", a) for a in arguments):
        return in_place_files(arguments, {"-e", "--expression", "-f", "--file"})
    if name == "perl" and any(re.fullmatch(r"-[a-hj-z]*i.*", a) for a in arguments):
        return in_place_files(arguments, {"-e", "-E"})
    if name in {"awk", "gawk"} and any(a == "-i" and b == "inplace" for a, b in zip(arguments, arguments[1:])):
        return in_place_files(arguments, {"-f", "-e"})
    if name == "patch":
        return ["."]
    if name == "curl":
        return downloads(arguments, "o", "O", {"-o", "--output"}, {"-O", "--remote-name", "--remote-name-all"})
    if name == "wget":
        to_stdout = any(a.endswith("O-") or a == "--output-document=-" for a in arguments) or any(
            a in {"-O", "--output-document"} and b == "-" for a, b in zip(arguments, arguments[1:]))
        return [] if to_stdout else downloads(arguments, "O", None, {"-O", "--output-document"}, set()) or ["."]
    if name in PACKAGE_TOOLS and places and places[0] in PACKAGE_CHANGES and not flags & FORMATTER_READ_FLAGS:
        return ["."]
    rewrites = (flags & FIX_FLAGS
                or name in FORMATTERS and not flags & FORMATTER_READ_FLAGS
                or name in {"gofmt", "clang-format", "autopep8"} and bool(flags & {"-w", "-i", "--in-place"})
                or name == "ruff" and places[:1] == ["format"] and not flags & FORMATTER_READ_FLAGS)
    if rewrites:
        return [p for p in places if p not in {"check", "format"}] or ["."]
    return []


def command_targets(words, cwds, variables, git_environment):
    """Returns the (kind, word) targets of one simple command, checking nested shell code."""
    words, fed_by_xargs = strip_prefix(words)
    if not words:
        return []
    name = os.path.basename(words[0])
    arguments = words[1:]
    places = positional(arguments)
    if name in SHELLS:
        for i, argument in enumerate(arguments[:-1]):
            if re.fullmatch(r"-[a-z]*c", argument):
                check_shell(arguments[i + 1], cwds)
        return []
    if name == "eval":
        check_shell(" ".join(arguments), cwds)
        return []
    if name == "watch":
        while arguments and arguments[0].startswith("-"):
            arguments = arguments[2:] if arguments[0] in WATCH_OPTIONS_WITH_VALUE else arguments[1:]
        check_shell(" ".join(arguments), cwds)
        return []
    if name == "git":
        return git_targets(arguments, git_environment)
    if name == "gh":
        if gh_change(places, arguments):
            raise Refused("changes code on a remote repository")
        return []
    if name == "find":
        paths = []
        for argument in arguments:
            if argument.startswith(("-", "(", "!")):
                break
            paths.append(argument)
        paths = paths or ["."]
        targets = [("path", p) for p in paths] if "-delete" in arguments else []
        targets += [("path", arguments[i + 1]) for i, a in enumerate(arguments[:-1]) if a in FIND_FILE_OUTPUT]
        for marker in FIND_EXEC:
            if marker in arguments:
                inner = arguments[arguments.index(marker) + 1:]
                inner = inner[:inner.index(";")] if ";" in inner else [w for w in inner if w != "+"]
                for path in paths:
                    targets += command_targets([path if w == "{}" else w for w in inner], cwds, variables, git_environment)
        return targets
    targets = [("path", t) for t in path_targets(name, arguments)]
    if fed_by_xargs and name in ALL_ARGUMENTS | ARGUMENTS_AFTER_FIRST:
        targets.append(("path", ""))
    return targets


def check_target(kind, word, cwds, variables):
    for cwd in cwds:
        try:
            path = resolve(word, cwd, variables)
        except UnknownPath:
            raise Refused(f"writes to a place the hook cannot name ({word or 'command output'})")
        if kind == "repository":
            path = enclosing_work_tree(os.path.realpath(path)) or path
        if is_protected(path):
            raise Refused(f"changes {path}")


def check_shell(command, cwds):
    """Raises Refused when the shell command changes code or documentation.

    cwds holds every folder the command may start in; None stands for one the
    hook cannot name. A cd counts for the rest of its && chain, and after that
    both the old and the new folder count.
    """
    variables = known_variables(command)
    git_environment = [m.strip("\"'") for m in re.findall(r"(?<![\w-])GIT_(?:DIR|WORK_TREE)=(\S+)", command)]
    current, possible, saved = set(cwds), set(cwds), []
    for words, redirections, separator in simple_commands(command):
        stripped, _ = strip_prefix(words)
        if stripped and os.path.basename(stripped[0]) in {"cd", "pushd", "popd"}:
            destination = positional(stripped[1:])
            moved = set()
            for cwd in current:
                try:
                    moved.add(None if stripped[0] == "popd" else HOME if not destination else resolve(destination[0], cwd, variables))
                except UnknownPath:
                    moved.add(None)
            possible |= moved
            current = moved if separator == "&&" else current | moved
        else:
            for kind, word in command_targets(words, current, variables, git_environment):
                check_target(kind, word, current, variables)
            for word in redirections:
                check_target("path", word, current, variables)
        if separator == "(":
            saved.append((set(current), set(possible)))
        elif separator == ")" and saved:
            current, possible = saved.pop()
        elif separator != "&&":
            current = set(possible)


def main():
    call = json.load(sys.stdin)
    if not call.get("agent_id"):
        return
    tool_name = call.get("tool_name", "")
    tool_input = call.get("tool_input") or {}
    cwd = call.get("cwd") or None
    try:
        if tool_name in {"EnterWorktree", "ExitWorktree"}:
            raise Refused("changes the repository's worktrees")
        if tool_name == "Agent" and tool_input.get("isolation") == "worktree":
            raise Refused("starts an agent in a new worktree of the repository")
        if tool_name in {"Edit", "Write", "NotebookEdit"}:
            path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
            if not path or is_protected(os.path.join(cwd or "/", path)):
                raise Refused(f"writes {path}")
        if tool_name in {"Bash", "Monitor"}:
            command = tool_input.get("command", "")
            if not isinstance(command, str):
                raise Refused("has a command the hook cannot read")
            try:
                check_shell(command, {cwd})
            except ValueError as error:
                raise Refused(f"cannot be read by the hook ({error})")
    except Refused as refused:
        print(refusal(str(refused)))


if __name__ == "__main__":
    main()
