#!/usr/bin/env python3
"""Validate markdown links to file paths with optional #L line anchors.

Supports both absolute paths (resolved as-is) and repo-relative paths
(resolved relative to each markdown file's parent directory).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


LINK_RE = re.compile(r"\]\(([^)#\s]+)(?:#L(\d+)(?:C\d+)?)?\)")
URL_SCHEME_RE = re.compile(r"^[a-z][a-z0-9+.-]*:", re.IGNORECASE)


def _resolve_target(raw: str, md_path: Path) -> Path:
    """Resolve a link target. Absolute paths used as-is; relative resolved against md_path's parent."""
    candidate = Path(raw)
    if candidate.is_absolute():
        return candidate
    return (md_path.parent / candidate).resolve()


def validate_file(md_path: Path) -> list[str]:
    errors: list[str] = []
    text = md_path.read_text(encoding="utf-8")
    line_count_cache: dict[Path, int] = {}

    for match in LINK_RE.finditer(text):
        raw = match.group(1)
        if URL_SCHEME_RE.match(raw):
            continue
        target = _resolve_target(raw, md_path)
        line = int(match.group(2)) if match.group(2) else None

        if not target.exists():
            errors.append(f"{md_path}: missing target {target}")
            continue

        if line is None:
            continue

        total = line_count_cache.get(target)
        if total is None:
            try:
                with target.open(encoding="utf-8") as fh:
                    total = sum(1 for _ in fh)
            except (OSError, UnicodeDecodeError) as exc:
                errors.append(f"{md_path}: cannot read {target}: {exc}")
                continue
            line_count_cache[target] = total

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
