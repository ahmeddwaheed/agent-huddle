import Foundation

enum StepKind {
    case terminal, edit, read, search, web, agent, other
}

struct Step: Identifiable, Equatable {
    let id: String
    let kind: StepKind
    let label: String
    var done = false
    var failed = false
}

struct TodoItem: Equatable {
    var id: String
    var title: String
    var activeForm: String?
    var status: String
}

struct TerminalSnapshot: Equatable {
    var command: String
    var output: String
}

struct QuestionOption: Hashable {
    let label: String
    let detail: String?
}

struct Question: Hashable {
    let text: String
    let header: String?
    let options: [QuestionOption]
    let multiSelect: Bool
}

struct PendingRequest: Identifiable {
    let id: String
    let sessionId: String
    let toolName: String
    let rawInput: [String: Any]
    let createdAt: Double
    let hookPid: Int32
    var suggestions: [[String: Any]] = []
    var agentType: String?

    var alwaysAllowLabel: String? {
        let parts = suggestions.compactMap(describeSuggestion)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var isQuestion: Bool { toolName == "AskUserQuestion" }

    var questions: [Question] {
        guard let list = rawInput["questions"] as? [[String: Any]] else { return [] }
        return list.map { q in
            let options = (q["options"] as? [[String: Any]] ?? []).map {
                QuestionOption(label: $0["label"] as? String ?? "", detail: $0["description"] as? String)
            }
            return Question(
                text: q["question"] as? String ?? "",
                header: q["header"] as? String,
                options: options,
                multiSelect: q["multiSelect"] as? Bool ?? false
            )
        }
    }

    var summary: String {
        let input = rawInput
        switch toolName {
        case "Bash":
            return "Bash: " + (input["command"] as? String ?? "")
        case "Edit", "Write", "Read", "NotebookEdit", "MultiEdit":
            let path = input["file_path"] as? String ?? input["notebook_path"] as? String ?? ""
            return "\(toolName): \(shortPath(path))"
        case "WebFetch":
            return "WebFetch: " + (input["url"] as? String ?? "")
        default:
            let pairs = input.keys.sorted().prefix(3).map { key -> String in
                let value = input[key].map { "\($0)" } ?? ""
                return "\(key): \(value.prefix(80))"
            }
            return ([prettyToolName(toolName)] + pairs).joined(separator: "\n")
        }
    }
}

struct AgentSession: Identifiable {
    let id: String
    let pid: Int32
    let cwd: String
    let startedAt: Double
    var name: String
    var status: String
    var statusUpdatedAt: Double
    var title: String?
    var steps: [Step] = []
    var todos: [TodoItem] = []
    var terminal: TerminalSnapshot?

    var isBusy: Bool { status == "busy" }
    var folder: String { (cwd as NSString).lastPathComponent }

    var displayTitle: String {
        if let title, !title.isEmpty { return "\(folder) · \(title)" }
        return name.isEmpty ? folder : name
    }

    var runningStep: Step? {
        guard isBusy, let last = steps.last, !last.done else { return nil }
        return last
    }

    var activeTodo: TodoItem? { todos.first { $0.status == "in_progress" } }
    var completedTodos: Int { todos.filter { $0.status == "completed" }.count }
}

func shortPath(_ path: String) -> String {
    let parts = path.split(separator: "/")
    return parts.suffix(2).joined(separator: "/")
}

func prettyToolName(_ name: String) -> String {
    guard name.hasPrefix("mcp__") else { return name }
    let parts = name.split(separator: "_", omittingEmptySubsequences: true)
    guard parts.count >= 3 else { return name }
    let server = parts[1]
    let tool = parts.dropFirst(2).joined(separator: "_")
    return "\(tool) (\(server))"
}

func describeSuggestion(_ suggestion: [String: Any]) -> String? {
    let place: String
    switch suggestion["destination"] as? String {
    case "session": place = "for this session"
    case "localSettings": place = "in this project (local)"
    case "projectSettings": place = "in this project"
    case "userSettings": place = "in all projects"
    default: place = ""
    }
    switch suggestion["type"] as? String {
    case "addRules", "replaceRules":
        let rules = (suggestion["rules"] as? [[String: Any]] ?? []).map { rule -> String in
            let tool = rule["toolName"] as? String ?? ""
            guard let content = rule["ruleContent"] as? String, !content.isEmpty else { return tool }
            return "\(tool)(\(content))"
        }
        guard !rules.isEmpty else { return nil }
        return "\(rules.joined(separator: ", ")) \(place)"
    case "addDirectories":
        let folders = (suggestion["directories"] as? [String] ?? []).map(shortPath)
        return "folder \(folders.joined(separator: ", ")) \(place)"
    case "setMode":
        let modes = ["acceptEdits": "auto-accept edits", "plan": "plan mode", "bypassPermissions": "skip all permission checks"]
        let mode = suggestion["mode"] as? String ?? ""
        return "\(modes[mode] ?? mode) \(place)"
    default:
        return nil
    }
}
