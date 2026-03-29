#!/usr/bin/env bash
# .qwen/install.sh
# Install metaswarm skills for Qwen Code CLI
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/dsifry/metaswarm/main/.qwen/install.sh | bash
#   # or
#   bash .qwen/install.sh  (from cloned repo)

set -euo pipefail

INSTALL_DIR="${QWEN_HOME:-$HOME/.qwen}/metaswarm"
SKILLS_DIR="$HOME/.qwen/skills"
REPO_URL="https://github.com/dsifry/metaswarm.git"

echo ""
echo "  metaswarm — Qwen Code CLI installer"
echo "  ===================================="
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

# Symlink skills
echo ""
echo "  Symlinking skills into $SKILLS_DIR..."
mkdir -p "$SKILLS_DIR"

linked=0
for skill_dir in "$INSTALL_DIR/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="metaswarm-$(basename "$skill_dir")"
  target="$SKILLS_DIR/$skill_name"

  if [ -L "$target" ]; then
    # Update existing symlink
    rm "$target"
  elif [ -d "$target" ]; then
    echo "  Warning: $target exists as a directory, skipping"
    continue
  fi

  ln -sf "$skill_dir" "$target"
  linked=$((linked + 1))
done

echo "  Linked $linked skills."

# Copy QWEN.md template if project doesn't have one
echo ""
if [ -f "QWEN.md" ] && grep -q "metaswarm" "QWEN.md" 2>/dev/null; then
  echo "  QWEN.md already has metaswarm section."
elif [ -f "QWEN.md" ]; then
  echo "  Note: QWEN.md exists but doesn't reference metaswarm."
  echo "  Run \$setup in your project to configure it."
else
  echo "  Note: No project-level QWEN.md created."
  echo "  Run \$setup in your project to set it up."
fi

echo ""
echo "  Done! metaswarm installed for Qwen Code CLI."
echo ""
echo "  Usage (Qwen uses the 'name' field from SKILL.md frontmatter):"
echo "    \$start                   Begin tracked work"
echo "    \$setup                   Configure for your project"
echo "    \$brainstorming-extension Refine an idea"
echo "    \$design-review-gate      Run design review"
echo ""
echo "  See .qwen/README.md for the full skill list."
echo ""
