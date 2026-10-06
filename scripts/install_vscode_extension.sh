#!/bin/zsh
# Installs the Nova Companion extension into VS Code (copies the folder into
# ~/.vscode/extensions). Restart VS Code afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="$HOME/.vscode/extensions/nova.nova-companion-0.1.0"
rm -rf "$DEST"
mkdir -p "$DEST"
cp extras/vscode-nova/package.json extras/vscode-nova/extension.js "$DEST/"
echo "Installed to $DEST. Restart VS Code (or run 'Developer: Reload Window')."
