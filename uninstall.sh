#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
SETTINGS="$HOME/.claude/settings.json"

pkill -x AgentHuddle 2>/dev/null || true
rm -rf "$HOME/Applications/Agent Huddle.app" "$HOME/.claude/huddle" "$HOME/Library/LaunchAgents/local.agent-huddle.plist"

python3 - "$SETTINGS" "python3 $ROOT/hook/huddle_permission.py" <<'PY'
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
settings = json.load(open(path))
hooks = settings.get("hooks", {})
groups = [g for g in hooks.get("PermissionRequest", []) if not any(h.get("command") == cmd for h in g.get("hooks", []))]
if groups:
    hooks["PermissionRequest"] = groups
else:
    hooks.pop("PermissionRequest", None)
json.dump(settings, open(path, "w"), indent=2)
print("Hook removed from", path)
PY
echo "Agent Huddle is removed."
