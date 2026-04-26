#!/usr/bin/env bash
# .codex/install.sh
# Install metaswarm skills for Codex CLI
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/dsifry/metaswarm/main/.codex/install.sh | bash
#   # or
#   bash .codex/install.sh  (from cloned repo)

set -euo pipefail

CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"
INSTALL_DIR="$CODEX_ROOT/metaswarm"
SKILLS_DIR="$CODEX_ROOT/skills"
REPO_URL="https://github.com/dsifry/metaswarm.git"

echo ""
echo "  metaswarm — Codex CLI installer"
echo "  ================================"
echo ""

# Check if already installed
if [ -d "$INSTALL_DIR" ]; then
  echo "  Updating existing installation at $INSTALL_DIR..."
  cd "$INSTALL_DIR"
  git pull --rebase origin main 2>/dev/null || {
    echo "  Warning: git pull failed. Removing and re-cloning..."
    cd /
    rm -rf "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
  }
else
  echo "  Cloning metaswarm..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# One-time sweep: remove dangling metaswarm-* symlinks from the legacy
# ~/.agents/skills location used by 0.10/0.11. Safe to run on machines
# that never had it (the directory check skips it).
LEGACY_AGENTS_DIR="$HOME/.agents/skills"
if [ -d "$LEGACY_AGENTS_DIR" ]; then
  legacy_removed=0
  # nullglob so an unmatched `metaswarm-*` glob expands to nothing instead of
  # iterating once over the literal pattern (which the symlink test would skip,
  # but cleaner to never iterate at all).
  shopt -s nullglob
  for legacy_link in "$LEGACY_AGENTS_DIR"/metaswarm-*; do
    [ -L "$legacy_link" ] || continue
    rm "$legacy_link"
    legacy_removed=$((legacy_removed + 1))
  done
  shopt -u nullglob
  if [ "$legacy_removed" -gt 0 ]; then
    echo "  Removed $legacy_removed legacy symlink(s) from $LEGACY_AGENTS_DIR."
  fi
fi

# Symlink skills
echo ""
echo "  Symlinking skills into $SKILLS_DIR..."
mkdir -p "$SKILLS_DIR"

linked=0
for skill_dir in "$INSTALL_DIR/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  target="$SKILLS_DIR/$skill_name"
  legacy_target="$SKILLS_DIR/metaswarm-$skill_name"

  if [ -L "$target" ]; then
    # Update existing symlink
    rm "$target"
  elif [ -d "$target" ]; then
    echo "  Warning: $target exists as a real directory (not a symlink); skipping."
    echo "           Remove it manually (rm -rf \"$target\") and re-run if you want the managed copy."
    continue
  fi

  if [ -L "$legacy_target" ]; then
    rm "$legacy_target"
  elif [ -e "$legacy_target" ]; then
    echo "  Warning: legacy path $legacy_target exists as a real directory; skipping $skill_name."
    echo "           Remove it manually (rm -rf \"$legacy_target\") and re-run to avoid"
    echo "           a duplicate skill entry alongside the new $target symlink."
    continue
  fi

  ln -sf "$skill_dir" "$target"
  linked=$((linked + 1))
done

echo "  Linked $linked skills."

# Copy AGENTS.md template if project doesn't have one
echo ""
if [ -f "AGENTS.md" ] && grep -q "metaswarm" "AGENTS.md" 2>/dev/null; then
  echo "  AGENTS.md already has metaswarm section."
elif [ -f "AGENTS.md" ]; then
  echo "  Note: AGENTS.md exists but doesn't reference metaswarm."
  echo "  Run \$setup in your project to configure it."
else
  echo "  Note: No project-level AGENTS.md created."
  echo "  Run \$setup in your project to set it up."
fi

echo ""
echo "  Done! metaswarm installed for Codex CLI."
echo ""
echo "  Usage (Codex uses the 'name' field from SKILL.md frontmatter):"
echo "    \$start                   Begin tracked work"
echo "    \$setup                   Configure for your project"
echo "    \$brainstorming-extension Refine an idea"
echo "    \$design-review-gate      Run 5-reviewer design review"
echo ""
echo "  See .codex/README.md for the full skill list."
echo ""
