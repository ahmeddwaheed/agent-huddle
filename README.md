# Agent Huddle

A small macOS menu bar widget that shows every Claude Code session you have running.

| All agents | Permission | Question | Step by step |
|---|---|---|---|
| ![All agents](docs/list.png) | ![A permission request](docs/permission.png) | ![A question from an agent](docs/question.png) | ![Detail view of one agent](docs/detail.png) |

- See each agent's current step, its task progress and a step-by-step log.
- Allow or deny permission requests without going back to the terminal.
- **Always allow** a command with one click (uses the same rule suggestions as Claude Code's "don't ask again").
- Deny with a note that tells Claude what to do instead.
- When one session has several requests at the same time (for example parallel subagents), they wait in a queue: "1 of 3", with arrows to move between them. Requests from a subagent show the subagent's name.
- Answer `AskUserQuestion` questions from the widget (single choice, multiple choice or your own text).
- Jump to the terminal that runs a session, or cross a session off when it is done.
- When an agent needs you, the widget opens by itself on that agent. It does not take keyboard focus from the app you use.
- Hear a sound when an agent needs you or finishes.
- Open or close it from anywhere with **⌃⌥A** (Control + Option + A).
- Sessions that have been idle for more than 1 hour go into one "done earlier" row.

### Keyboard

| Key | Action |
|---|---|
| ⌃⌥A | Open or close the widget (opens on the agent that needs you) |
| ↩ | Allow, or send the answer |
| A | Always allow |
| D | Deny (with your note, if you typed one) |
| 1–9 | Pick an answer option |
| ← → | Move between requests from the same session |
| Esc | Close |

Text fields take focus only when you click them, so the keys above always work.

The prompt still shows in your terminal too. Answer wherever is closer; the other side clears itself.

## Requirements

- macOS 14 or later
- Swift toolchain (Xcode or the Command Line Tools: `xcode-select --install`)
- `python3`
- Claude Code with the `~/.claude/sessions` folder (recent versions)

## Install

```sh
git clone https://github.com/ahmeddwaheed/agent-huddle.git
cd agent-huddle
./install.sh
```

`install.sh` does four things:

1. Builds the app and puts it in `~/Applications/Agent Huddle.app`.
2. Adds a `PermissionRequest` hook to `~/.claude/settings.json` (a backup goes to `settings.json.huddle-backup`).
3. Adds a login item (`~/Library/LaunchAgents/local.agent-huddle.plist`) so the widget starts when you log in.
4. Starts the app. Look for the robot in the menu bar, or press **⌃⌥A** (Control + Option + A) to open it.

Run `./install.sh` again after you change the code.

## Uninstall

```sh
./uninstall.sh
```

This removes the app, the hook entry, the login item and `~/.claude/huddle`.

## How it works

```
Claude Code session ──PermissionRequest hook──▶ ~/.claude/huddle/pending/<id>.json
                                                        │
Agent Huddle (menu bar) ◀── reads ──────────────────────┘
        │  you click Allow / Deny / Send
        ▼
~/.claude/huddle/responses/<id>.json ──▶ hook prints the decision ──▶ Claude Code continues
```

- **Sessions** come from `~/.claude/sessions/*.json` (one file per live session).
- **Steps, tasks and terminal output** come from the session transcript in `~/.claude/projects/`.
  For big transcripts the widget reads only the last 3 MB.
- **Request files are private** (`~/.claude/huddle` is `700`), because commands can contain secrets.
- **The hook only waits while the widget runs.** The widget writes a heartbeat file every second.
  If the widget is not running, the hook returns at once and Claude Code asks in the terminal as usual.
- **If you answer in the terminal**, the hook sees the tool result in the transcript and stops waiting.
- **Jump** walks up the process tree to find the app that hosts the session and brings it to the front.
  iTerm2 also selects the exact tab. Herdr also focuses the exact pane.

## Debug

Save a picture of the widget without screen-recording permission:

```sh
HUDDLE_SNAPSHOT=/tmp/huddle.png .build/release/AgentHuddle
HUDDLE_DETAIL=1 HUDDLE_SNAPSHOT=/tmp/detail.png .build/release/AgentHuddle
```

Show demo data instead of your real sessions (used for the README pictures):

```sh
HUDDLE_DEMO=list HUDDLE_SNAPSHOT=docs/list.png .build/release/AgentHuddle
HUDDLE_DEMO=permission HUDDLE_SNAPSHOT=docs/permission.png .build/release/AgentHuddle
HUDDLE_DEMO=question HUDDLE_SNAPSHOT=docs/question.png .build/release/AgentHuddle
HUDDLE_DEMO=detail HUDDLE_DETAIL=1 HUDDLE_SNAPSHOT=docs/detail.png .build/release/AgentHuddle
```

Test the key actions against a real hook request (no Accessibility permission needed):

```sh
HUDDLE_TEST_SESSION=<session id of your test request> HUDDLE_TEST_KEYS="2,return" .build/release/AgentHuddle
```

## License

MIT
