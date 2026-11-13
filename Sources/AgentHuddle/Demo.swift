import Foundation

enum Demo {
    static var mode: String? { ProcessInfo.processInfo.environment["HUDDLE_DEMO"] }

    static func sessions() -> [AgentSession] {
        let now = Date().timeIntervalSince1970 * 1000
        var api = AgentSession(id: "demo-api", pid: 0, cwd: "/work/api", startedAt: 1, name: "", status: "busy", statusUpdatedAt: now)
        api.title = "Move auth to JWT"
        api.todos = [
            TodoItem(id: "1", title: "Read the current session code", activeForm: nil, status: "completed"),
            TodoItem(id: "2", title: "Add token signing", activeForm: nil, status: "completed"),
            TodoItem(id: "3", title: "Add refresh endpoint", activeForm: nil, status: "completed"),
            TodoItem(id: "4", title: "Update middleware", activeForm: nil, status: "completed"),
            TodoItem(id: "5", title: "Write refresh tests", activeForm: "Writing refresh tests", status: "in_progress"),
            TodoItem(id: "6", title: "Remove old sessions table", activeForm: nil, status: "pending"),
        ]
        api.steps = [
            Step(id: "a1", kind: .read, label: "Read auth/session.ts", done: true),
            Step(id: "a2", kind: .edit, label: "Edit auth/jwt.ts", done: true),
            Step(id: "a3", kind: .edit, label: "Write auth/refresh.ts", done: true),
            Step(id: "a4", kind: .search, label: "Search requireSession", done: true),
            Step(id: "a5", kind: .edit, label: "Edit middleware/auth.ts", done: true),
            Step(id: "a6", kind: .terminal, label: "Run auth tests", done: true),
            Step(id: "a7", kind: .edit, label: "Write refresh.test.ts", done: false),
        ]
        api.terminal = TerminalSnapshot(command: "npm test -- auth", output: "PASS  auth/jwt.test.ts (12 tests)\nPASS  auth/middleware.test.ts (8 tests)\nTests: 20 passed, 20 total")

        var web = AgentSession(id: "demo-web-2", pid: 0, cwd: "/work/web", startedAt: 2, name: "", status: "busy", statusUpdatedAt: now)
        web.title = "Dark mode polish"
        web.steps = (1...14).map { Step(id: "w\($0)", kind: .edit, label: "Edit theme.css", done: true) }

        var infra = AgentSession(id: "demo-infra-7", pid: 0, cwd: "/work/infra", startedAt: 3, name: "", status: "busy", statusUpdatedAt: now)
        infra.title = "Fix flaky CI"
        infra.todos = [
            TodoItem(id: "1", title: "Find the flaky test", activeForm: nil, status: "completed"),
            TodoItem(id: "2", title: "Reproduce locally", activeForm: "Starting the test database", status: "in_progress"),
            TodoItem(id: "3", title: "Fix and verify", activeForm: nil, status: "pending"),
        ]
        infra.steps = (1...9).map { Step(id: "i\($0)", kind: .terminal, label: "Run tests", done: true) }

        var docs = AgentSession(id: "demo-docs-1", pid: 0, cwd: "/work/docs", startedAt: 4, name: "", status: "idle", statusUpdatedAt: now)
        docs.title = "Release notes"
        docs.steps = (1...23).map { Step(id: "d\($0)", kind: .read, label: "Read CHANGELOG.md", done: true) }

        return [api, web, infra, docs]
    }

    static func pending() -> [PendingRequest] {
        switch mode {
        case "permission":
            return [PendingRequest(
                id: "demo-perm", sessionId: "demo-infra-7", toolName: "Bash",
                rawInput: ["command": "docker compose up -d postgres"], createdAt: 1, hookPid: 0
            )]
        case "question":
            return [PendingRequest(
                id: "demo-question", sessionId: "demo-web-2", toolName: "AskUserQuestion",
                rawInput: ["questions": [[
                    "question": "Which accent color should dark mode use?",
                    "header": "Theme",
                    "multiSelect": false,
                    "options": [
                        ["label": "Lime", "description": "Matches the brand"],
                        ["label": "Sky blue"],
                        ["label": "Keep the light mode color"],
                    ],
                ]]],
                createdAt: 1, hookPid: 0
            )]
        default:
            return []
        }
    }
}
