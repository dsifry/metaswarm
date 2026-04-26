#!/usr/bin/env python3
"""Validate markdown links that point to absolute file paths with optional #L anchors."""

from __future__ import annotations

import re
import sys
from pathlib import Path


LINK_RE = re.compile(r"\]\((/[^)#]+)(?:#L(\d+)(?:C\d+)?)?\)")


def validate_file(md_path: Path) -> list[str]:
    errors: list[str] = []
    text = md_path.read_text(encoding="utf-8")
    for match in LINK_RE.finditer(text):
        target = Path(match.group(1))
        line = int(match.group(2)) if match.group(2) else None

        if not target.exists():
            errors.append(f"{md_path}: missing target {target}")
            continue

        if line is not None:
            with target.open(encoding="utf-8") as f:
                total = sum(1 for _ in f)
            if not (1 <= line <= total):
                errors.append(f"{md_path}: {target}#L{line} out of range (1..{total})")
    return errors


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: validate_line_links.py <markdown-file> [<markdown-file> ...]", file=sys.stderr)
        return 2

    errors: list[str] = []
    checked = 0
    for arg in argv[1:]:
        md_path = Path(arg)
        if not md_path.exists():
            errors.append(f"missing markdown file {md_path}")
            continue
        checked += 1
        errors.extend(validate_file(md_path))

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"validated {checked} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
