#!/usr/bin/env python3
"""PreToolUse guard: Claude may read FocusContinuity's live data, never change it.

The live data is the user's real history: sessions.json and app-usage.json in
Application Support, and the app's own preferences domain. Checks and probes
use a scratch archive and an isolated `fc-selftest-…` defaults suite instead.
The self-test suites (`com.prabesh.focuscontinuity.selftest.*`) are not live
data and are not guarded.

This is a guardrail against slips, not a sandbox: it reads the command text,
so indirection (scripts, xargs, $(...)) can get past it. A command that
carries FC_LIVE_DATA_OK=1 is let through; use it only when the user has asked
for that exact change in the conversation.

Exit 2 blocks the tool call and shows the reason to Claude.
"""
import fnmatch
import json
import os
import re
import shlex
import sys

HOME = os.path.expanduser("~")
DOMAIN = "com.prabesh.focuscontinuity"
LIVE = [
    os.path.join(HOME, "Library/Application Support/FocusContinuity"),
    os.path.join(HOME, "Library/Preferences", DOMAIN + ".plist"),
]
BYPASS = "FC_LIVE_DATA_OK=1"

# Verbs that change whatever path they are given.
CHANGES_ANY = {"rm", "rmdir", "unlink", "shred", "trash", "truncate",
               "touch", "mkdir", "chmod", "chown", "tee", "xattr"}
# Verbs that only change their last argument (the destination).
CHANGES_DEST = {"cp", "rsync", "ditto", "install", "ln"}
# Verbs that also take out everything beneath an ancestor directory.
REMOVES_TREE = {"rm", "trash"}
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "|&"}
WRAPPERS = {"sudo", "command", "nohup", "time", "env", "exec"}


def expand(word):
    word = word.replace("${HOME}", HOME).replace("$HOME", HOME)
    if word == "~" or word.startswith("~/"):
        word = HOME + word[1:]
    return os.path.normpath(word) if word.startswith("/") else word


def touches(word, *, ancestors=False):
    """True when the path names live data, lies inside it, or (for removals)
    contains it."""
    path = expand(word)
    if not path.startswith("/"):
        return False
    for live in LIVE:
        if path == live or path.startswith(live + "/"):
            return True
        if any(c in path for c in "*?[") and fnmatch.fnmatch(live, path):
            return True
        if ancestors and live.startswith(path.rstrip("/") + "/"):
            return True
    return False


def names_live_domain(word):
    return re.fullmatch(re.escape(DOMAIN) + r"(\.plist)?", word) is not None or touches(word)


def segments(command):
    for line in command.replace("\\\n", " ").splitlines():
        lexer = shlex.shlex(line, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        lexer.commenters = ""
        current = []
        for token in lexer:
            if token in SEPARATORS:
                if current:
                    yield current
                current = []
            else:
                current.append(token)
        if current:
            yield current


def blocked_segment(words):
    # Redirections: `> file`, `>> file`, `>| file`.
    for i, word in enumerate(words[:-1]):
        if word in {">", ">>", ">|", "&>", "&>>"} and touches(words[i + 1]):
            return f"redirects output into {words[i + 1]}"

    while words and (words[0] in WRAPPERS or re.fullmatch(r"[A-Za-z_]\w*=.*", words[0])):
        words = words[1:]
    if not words:
        return None
    verb, args = os.path.basename(words[0]), [w for w in words[1:] if w not in {">", ">>"}]
    operands = [a for a in args if not a.startswith("-")]

    if verb in CHANGES_ANY and any(touches(a, ancestors=verb in REMOVES_TREE) for a in operands):
        return f"`{verb}` changes live data"
    # mv takes its sources away (and anything inside them) and writes its destination.
    if verb == "mv" and operands and (any(touches(a, ancestors=True) for a in operands[:-1])
                                      or touches(operands[-1])):
        return "`mv` moves live data"
    if verb in CHANGES_DEST and operands and touches(operands[-1]):
        return f"`{verb}` writes into live data"
    if verb in {"sed", "perl"} and any(a.startswith("-i") for a in args) \
            and any(touches(a) for a in operands):
        return f"`{verb} -i` edits live data in place"
    if verb == "plutil" and any(a in {"-replace", "-remove", "-insert", "-convert", "-create"}
                                for a in args) and any(touches(a) for a in operands):
        return "`plutil` edits the live preferences file"
    if verb == "find" and any(touches(a, ancestors=True) for a in operands) \
            and any(a in {"-delete", "-exec", "-execdir"} for a in args):
        return "`find` would change files under live data"
    if verb == "defaults" and operands[:1] and operands[0] in {"write", "delete", "rename", "import"} \
            and len(operands) > 1 and names_live_domain(operands[1]):
        return f"`defaults {operands[0]}` changes the app's live preferences"
    return None


def reasons_for(tool, params):
    if tool == "Bash":
        command = params.get("command", "")
        if BYPASS in command:
            return []
        try:
            return [r for r in map(blocked_segment, segments(command)) if r]
        except ValueError:
            # Unbalanced quotes: refuse only when live data is named at all.
            mentions = "Application Support/FocusContinuity" in command.replace("\\ ", " ") \
                or DOMAIN + ".plist" in command
            return ["the command could not be parsed and names live data"] if mentions else []
    path = params.get("file_path") or params.get("notebook_path") or ""
    return [f"{tool} would change {path}"] if path and touches(path) else []


def check():
    """`python3 guard-live-data.py --check`: every case must land on its side."""
    data = "~/Library/Application\\ Support/FocusContinuity"
    blocked = [
        f"rm -rf {data}",
        'rm "$HOME/Library/Application Support/FocusContinuity/sessions.json"',
        f"mv {data} /tmp/old",
        f"echo '{{}}' > {data}/app-usage.json",
        f"cp /tmp/a.json {data}/sessions.json",
        f"cd /tmp && rm -rf {data}",
        f"sed -i '' s/a/b/ {data}/sessions.json",
        "find ~/Library/Application\\ Support -name '*.json' -delete",
        "defaults write com.prabesh.focuscontinuity fc.goal 3",
        "defaults delete com.prabesh.focuscontinuity",
        "rm ~/Library/Preferences/com.prabesh.focuscontinuity*",
        "rm -rf ~",
    ]
    allowed = [
        f"ls {data}",
        f"cat {data}/sessions.json | jq length",
        f"cp {data}/sessions.json /tmp/backup.json",
        "defaults read com.prabesh.focuscontinuity",
        "defaults delete com.prabesh.focuscontinuity.selftest.123",
        "rm ~/Library/Preferences/com.prabesh.focuscontinuity.selftest.42.plist",
        "mv /tmp/x ~/Library/",
        "rm -rf /tmp/fc-selftest-abc",
        "./build.sh --check 2>&1 | tail -5",
        f"FC_LIVE_DATA_OK=1 rm {data}/stale.tmp",
    ]
    live_file = os.path.join(LIVE[0], "sessions.json")
    failures = [f"not blocked: {c}" for c in blocked if not reasons_for("Bash", {"command": c})]
    failures += [f"blocked: {c}" for c in allowed if reasons_for("Bash", {"command": c})]
    if not reasons_for("Write", {"file_path": live_file}):
        failures.append("Write to the live sessions.json was not blocked")
    if reasons_for("Edit", {"file_path": os.path.abspath("Sources/SelfTest.swift")}):
        failures.append("Edit to a source file was blocked")
    print("\n".join(failures) or f"ok: {len(blocked) + len(allowed) + 2} cases")
    return 1 if failures else 0


def main():
    if sys.argv[1:] == ["--check"]:
        return check()
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    reasons = reasons_for(tool, data.get("tool_input") or {})
    if not reasons:
        return 0
    print(
        "Blocked: " + "; ".join(reasons) + ".\n"
        "This is FocusContinuity's live data (the user's real history and settings). "
        "Use a scratch archive (SelfTest.scratchDirectory()) and an isolated "
        "`fc-selftest-…` UserDefaults suite instead. Reading is fine. If the user has "
        "asked for this exact change in the conversation, re-run with "
        f"{BYPASS} in the command.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
