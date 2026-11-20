#!/usr/bin/env python3
"""Turn a release-notes Markdown file into the HTML Sparkle shows in the update window.

Supports only what release notes use: `##` and `###` headings, `- ` bullets,
`1. ` numbered items, `**bold**`, `` `code` `` and plain paragraphs.
Usage: notes-to-html.py notes.md
"""
import html
import re
import sys


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", text)


out, open_list = [], None


def close():
    global open_list
    if open_list:
        out.append(f"</{open_list}>")
        open_list = None


for line in open(sys.argv[1], encoding="utf-8").read().splitlines():
    line = line.rstrip()
    bullet = re.match(r"^\s*[-*] (.+)", line)
    number = re.match(r"^\s*\d+\. (.+)", line)
    heading = re.match(r"^(#{2,3}) (.+)", line)
    if bullet or number:
        kind = "ul" if bullet else "ol"
        if open_list != kind:
            close()
            out.append(f"<{kind}>")
            open_list = kind
        out.append(f"<li>{inline((bullet or number).group(1))}</li>")
        continue
    close()
    if heading:
        level = len(heading.group(1)) + 1  # ## -> h3, ### -> h4
        out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
    elif line:
        out.append(f"<p>{inline(line)}</p>")
close()
print("".join(out))
