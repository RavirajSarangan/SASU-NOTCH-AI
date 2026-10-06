#!/bin/zsh
# Installs Nova's hook into Claude Code (~/.claude/settings.json).
#   scripts/install_claude_hook.sh --dry-run   show the change only
#   scripts/install_claude_hook.sh             install (backs up settings first)
#
# The hook is safe when Nova isn't running: it exits silently and Claude Code
# behaves normally. It never approves anything by itself.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

DEST_DIR="$HOME/Library/Application Support/Nova/bin"
HOOK="$DEST_DIR/nova-hook"
SETTINGS="$HOME/.claude/settings.json"

if [[ $DRY_RUN == 0 ]]; then
  swift build -c release --product nova-hook >/dev/null
  BIN="$(swift build -c release --show-bin-path)"
  mkdir -p "$DEST_DIR"
  cp "$BIN/nova-hook" "$HOOK"
  codesign --force --sign - "$HOOK" >/dev/null
  echo "Installed helper: $HOOK"
fi

python3 - "$SETTINGS" "$HOOK" "$DRY_RUN" <<'PY'
import json, os, shutil, sys, time
settings_path, hook, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
command = f'"{hook}"'
events = {
    "SessionStart": 5, "UserPromptSubmit": 5, "PreToolUse": 5, "PostToolUse": 5,
    "PostToolUseFailure": 5, "Notification": 5, "Stop": 5, "StopFailure": 5, "SessionEnd": 2,
    "PermissionRequest": 130,   # waits for your click in Nova (Nova gives up after 120 s)
}
original = ""
data = {}
if os.path.exists(settings_path):
    original = open(settings_path).read()
    data = json.loads(original) if original.strip() else {}
hooks = data.setdefault("hooks", {})
for event, timeout in events.items():
    groups = hooks.setdefault(event, [])
    # Drop any previous Nova entry so re-running is idempotent.
    for group in groups:
        group["hooks"] = [h for h in group.get("hooks", []) if "nova-hook" not in h.get("command", "")]
    groups[:] = [g for g in groups if g.get("hooks")]
    entry = {"type": "command", "command": command, "timeout": timeout}
    groups.append({"matcher": ".*", "hooks": [entry]} if event in ("PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest") else {"hooks": [entry]})
    if event == "PreToolUse":
        # Claude's questions (AskUserQuestion) are answered in the notch:
        # this entry waits up to 5 minutes for your answer.
        groups.append({"matcher": "AskUserQuestion",
                       "hooks": [{"type": "command", "command": f'{command} --ask', "timeout": 310}]})
updated = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
if dry:
    # Show only Nova's entries, never the rest of the user's settings.
    nova = {e: [g for g in hooks[e] if any("nova-hook" in h.get("command", "") for h in g["hooks"])] for e in events}
    others = sum(len(g.get("hooks", [])) for e, gs in hooks.items() for g in gs) - len(events) - 1
    print(json.dumps({"hooks (Nova entries to add)": nova}, indent=2))
    print(f"Existing hooks kept untouched: {others}. All other settings unchanged.")
    sys.exit(0)
if original:
    backup = f"{settings_path}.nova-backup-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(settings_path, backup)
    print(f"Backed up settings to {backup}")
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
open(settings_path, "w").write(updated)
print(f"Updated {settings_path}. Start a new Claude Code session to pick it up.")
PY
