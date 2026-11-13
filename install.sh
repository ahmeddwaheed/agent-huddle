#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$HOME/Applications/Agent Huddle.app"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD="python3 $ROOT/hook/huddle_permission.py"

swift build -c release --package-path "$ROOT"

pkill -x AgentHuddle 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/AgentHuddle" "$APP/Contents/MacOS/AgentHuddle"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Agent Huddle</string>
  <key>CFBundleIdentifier</key><string>local.agent-huddle</string>
  <key>CFBundleExecutable</key><string>AgentHuddle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Agent Huddle selects the right terminal tab when you jump to a session.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null

[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.huddle-backup"
python3 - "$SETTINGS" "$HOOK_CMD" <<'PY'
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
settings = json.load(open(path))
groups = settings.setdefault("hooks", {}).setdefault("PermissionRequest", [])
already = any(h.get("command") == cmd for g in groups for h in g.get("hooks", []))
if not already:
    groups.append({"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": 600}]})
    json.dump(settings, open(path, "w"), indent=2)
    print("Hook added to", path)
else:
    print("Hook already present")
PY

AGENT="$HOME/Library/LaunchAgents/local.agent-huddle.plist"
mkdir -p "${AGENT:h}"
cat > "$AGENT" <<AGENT_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.agent-huddle</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$APP</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
AGENT_PLIST

open "$APP"
echo "Agent Huddle is running. Look for the robot in the menu bar."
