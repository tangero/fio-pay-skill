#!/bin/bash
# FIO Pay Skill instalátor pro Claude Code
# Použití: ./install.sh  nebo  curl -fsSL <url>/install.sh | bash

set -e

COMMANDS_DIR="$HOME/.claude/commands"
SKILL_FILE="fio-setup.md"
REPO_URL="https://raw.githubusercontent.com/tangero/fio-pay-skill/main"

echo "🏦 Instaluji FIO Pay Skill pro Claude Code..."

# Vytvoření adresáře pro commands
mkdir -p "$COMMANDS_DIR"

# Zjištění zdroje: lokální soubor (git clone) nebo vzdálený (curl pipe)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null || echo ".")" && pwd)"

if [ -f "$SCRIPT_DIR/$SKILL_FILE" ]; then
  # Lokální instalace (git clone)
  cp "$SCRIPT_DIR/$SKILL_FILE" "$COMMANDS_DIR/$SKILL_FILE"
  echo "✅ Nainstalováno z lokálního souboru"
else
  # Vzdálená instalace (curl)
  curl -fsSL "$REPO_URL/$SKILL_FILE" -o "$COMMANDS_DIR/$SKILL_FILE"
  echo "✅ Staženo z GitHubu"
fi

echo ""
echo "✅ FIO Pay Skill úspěšně nainstalován!"
echo ""
echo "   Umístění: $COMMANDS_DIR/$SKILL_FILE"
echo ""
echo "   Použití: Otevřete jakýkoliv projekt v Claude Code a napište:"
echo "   /fio-setup"
echo ""
