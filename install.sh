#!/bin/bash
# FIO Pay Skill installer for Claude Code
# Usage: ./install.sh  or  curl -fsSL <url>/install.sh | bash

set -e

COMMANDS_DIR="$HOME/.claude/commands"
SKILL_FILE="fio-setup.md"
REPO_URL="https://raw.githubusercontent.com/tangero/fio-pay-skill/main"

echo "🏦 Installing FIO Pay Skill for Claude Code..."

# Create commands directory
mkdir -p "$COMMANDS_DIR"

# Determine source: local file (git clone) or remote (curl pipe)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null || echo ".")" && pwd)"

if [ -f "$SCRIPT_DIR/$SKILL_FILE" ]; then
  # Local install (git clone)
  cp "$SCRIPT_DIR/$SKILL_FILE" "$COMMANDS_DIR/$SKILL_FILE"
  echo "✅ Installed from local file"
else
  # Remote install (curl)
  curl -fsSL "$REPO_URL/$SKILL_FILE" -o "$COMMANDS_DIR/$SKILL_FILE"
  echo "✅ Downloaded from GitHub"
fi

echo ""
echo "✅ FIO Pay Skill installed successfully!"
echo ""
echo "   Location: $COMMANDS_DIR/$SKILL_FILE"
echo ""
echo "   Usage: Open any project in Claude Code and type:"
echo "   /fio-setup"
echo ""
