#!/bin/bash
# PostToolUse: a Swift file Claude has just written must still parse.
# `swiftc -parse` takes under a second per file and catches a stray or missing
# brace left by a text edit. The full typecheck (~100 s) is left to
# ./build.sh --check. Exit 2 shows the errors to Claude.
file=$(python3 -c 'import json, sys; print((json.load(sys.stdin).get("tool_input") or {}).get("file_path", ""))')
[[ "$file" == *.swift && -f "$file" ]] || exit 0
if ! output=$(swiftc -parse "$file" 2>&1); then
  printf 'swiftc -parse failed for %s:\n%s\n' "$file" "$(printf '%s\n' "$output" | head -30)" >&2
  exit 2
fi
