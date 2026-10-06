#!/bin/zsh
# Removes Nova's entries from ~/.claude/settings.json (backs up first).
set -euo pipefail
SETTINGS="$HOME/.claude/settings.json"
[[ -f "$SETTINGS" ]] || { echo "No $SETTINGS"; exit 0; }
python3 - "$SETTINGS" <<'PY'
import json, shutil, sys, time
path = sys.argv[1]
data = json.load(open(path))
hooks = data.get("hooks", {})
removed = 0
for event in list(hooks):
    for group in hooks[event]:
        before = len(group.get("hooks", []))
        group["hooks"] = [h for h in group.get("hooks", []) if "nova-hook" not in h.get("command", "")]
        removed += before - len(group["hooks"])
    hooks[event] = [g for g in hooks[event] if g.get("hooks")]
    if not hooks[event]:
        del hooks[event]
if not hooks:
    data.pop("hooks", None)
shutil.copy2(path, f"{path}.nova-backup-{time.strftime('%Y%m%d-%H%M%S')}")
json.dump(data, open(path, "w"), indent=2, ensure_ascii=False)
print(f"Removed {removed} Nova hook entries.")
PY
rm -f "$HOME/Library/Application Support/Nova/bin/nova-hook"
