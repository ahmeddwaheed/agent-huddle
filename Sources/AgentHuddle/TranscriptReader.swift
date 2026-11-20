import Foundation

final class TranscriptReader {
    let url: URL
    private var offset: UInt64 = 0
    private var remainder = Data()
    private var stepIndex: [String: Int] = [:]
    private var bashCommands: [String: String] = [:]
    private var taskCreateIds: [String: String] = [:]
    private var aiTitle: String?
    private var customTitle: String?
    private var firstPrompt: String?

    private(set) var steps: [Step] = []
    private(set) var todos: [TodoItem] = []
    private(set) var terminal: TerminalSnapshot?

    var title: String? { customTitle ?? aiTitle ?? firstPrompt }

    private static let maxSteps = 200
    private static let initialTailBytes: UInt64 = 3 * 1024 * 1024

    init(url: URL) {
        self.url = url
    }

    @discardableResult
    func refresh() -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { reset() }
        guard size > offset else { return false }
        let skipPartialLine = offset == 0 && size > Self.initialTailBytes
        if skipPartialLine { offset = size - Self.initialTailBytes }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return false }
        offset += UInt64(data.count)

        var lines = (remainder + data).split(separator: 0x0A, omittingEmptySubsequences: false)
        if skipPartialLine, !lines.isEmpty { lines.removeFirst() }
        remainder = Data(lines.last ?? Data())
        for line in lines.dropLast() where !line.isEmpty {
            parse(Data(line))
        }
        if steps.count > Self.maxSteps {
            steps.removeFirst(steps.count - Self.maxSteps)
            stepIndex = Dictionary(uniqueKeysWithValues: steps.enumerated().map { ($1.id, $0) })
        }
        return true
    }

    private func reset() {
        offset = 0
        remainder = Data()
        steps = []
        stepIndex = [:]
        todos = []
        terminal = nil
        bashCommands = [:]
        taskCreateIds = [:]
    }

    private func parse(_ line: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        if obj["isSidechain"] as? Bool == true { return }
        switch obj["type"] as? String {
        case "ai-title":
            aiTitle = obj["aiTitle"] as? String
        case "custom-title":
            customTitle = obj["customTitle"] as? String
        case "assistant":
            for block in contentBlocks(obj) where block["type"] as? String == "tool_use" {
                handleToolUse(block)
            }
        case "user":
            if firstPrompt == nil, obj["isMeta"] as? Bool != true, let prompt = promptText(obj) {
                firstPrompt = prompt
            }
            for block in contentBlocks(obj) where block["type"] as? String == "tool_result" {
                handleToolResult(block, extra: obj["toolUseResult"])
            }
        default:
            break
        }
    }

    private func promptText(_ obj: [String: Any]) -> String? {
        let content = (obj["message"] as? [String: Any])?["content"]
        let raw: String
        if let text = content as? String {
            raw = text
        } else if let blocks = content as? [[String: Any]], !blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
            raw = blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
        } else {
            return nil
        }
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty, !line.hasPrefix("<"), !line.hasPrefix("[Image") else { return nil }
        return line.count > 60 ? String(line.prefix(57)) + "…" : line
    }

    private func contentBlocks(_ obj: [String: Any]) -> [[String: Any]] {
        let message = obj["message"] as? [String: Any]
        return message?["content"] as? [[String: Any]] ?? []
    }

    private func handleToolUse(_ block: [String: Any]) {
        guard let id = block["id"] as? String, let name = block["name"] as? String else { return }
        let input = block["input"] as? [String: Any] ?? [:]

        switch name {
        case "TodoWrite":
            let list = input["todos"] as? [[String: Any]] ?? []
            todos = list.enumerated().map { index, item in
                TodoItem(
                    id: String(index),
                    title: item["content"] as? String ?? "",
                    activeForm: item["activeForm"] as? String,
                    status: item["status"] as? String ?? "pending"
                )
            }
        case "TaskCreate":
            let todo = TodoItem(
                id: String(todos.count + 1),
                title: input["subject"] as? String ?? "",
                activeForm: input["activeForm"] as? String,
                status: "pending"
            )
            todos.append(todo)
            taskCreateIds[id] = todo.id
        case "TaskUpdate":
            let taskId = "\(input["taskId"] ?? "")"
            if let index = todos.firstIndex(where: { $0.id == taskId }) {
                if let status = input["status"] as? String { todos[index].status = status }
                if let subject = input["subject"] as? String { todos[index].title = subject }
                if let active = input["activeForm"] as? String { todos[index].activeForm = active }
            }
            if input["status"] as? String == "deleted" { todos.removeAll { $0.id == taskId } }
        default:
            break
        }

        if name == "Bash" {
            bashCommands[id] = input["command"] as? String ?? ""
        }
        stepIndex[id] = steps.count
        steps.append(Step(id: id, kind: kind(for: name), label: label(for: name, input: input)))
    }

    private func handleToolResult(_ block: [String: Any], extra: Any?) {
        guard let id = block["tool_use_id"] as? String else { return }
        if let index = stepIndex[id], index < steps.count {
            steps[index].done = true
            steps[index].failed = block["is_error"] as? Bool ?? false
        }
        if let createdLocalId = taskCreateIds.removeValue(forKey: id),
           let realId = firstNumber(in: resultText(block)),
           let index = todos.firstIndex(where: { $0.id == createdLocalId }) {
            todos[index].id = realId
        }
        if let command = bashCommands.removeValue(forKey: id) {
            var output = resultText(block)
            if let result = extra as? [String: Any] {
                let stdout = result["stdout"] as? String ?? ""
                let stderr = result["stderr"] as? String ?? ""
                output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            }
            let tail = output.split(separator: "\n", omittingEmptySubsequences: true).suffix(6).joined(separator: "\n")
            terminal = TerminalSnapshot(command: command, output: tail)
        }
    }

    private func resultText(_ block: [String: Any]) -> String {
        if let text = block["content"] as? String { return text }
        let parts = block["content"] as? [[String: Any]] ?? []
        return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    private func firstNumber(in text: String) -> String? {
        guard let hash = text.firstIndex(of: "#") else { return nil }
        let digits = text[text.index(after: hash)...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    private func kind(for name: String) -> StepKind {
        switch name {
        case "Bash", "BashOutput", "KillShell": return .terminal
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return .edit
        case "Read": return .read
        case "Grep", "Glob", "ToolSearch": return .search
        case "WebFetch", "WebSearch": return .web
        case "Agent", "Task", "SendMessage": return .agent
        default: return .other
        }
    }

    private func label(for name: String, input: [String: Any]) -> String {
        let file = shortPath(input["file_path"] as? String ?? input["notebook_path"] as? String ?? "")
        switch name {
        case "Bash":
            if let description = input["description"] as? String, !description.isEmpty { return description }
            return (input["command"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? "Run command"
        case "Read": return "Read \(file)"
        case "Edit", "MultiEdit": return "Edit \(file)"
        case "Write": return "Write \(file)"
        case "NotebookEdit": return "Edit notebook \(file)"
        case "Grep", "Glob": return "Search \(input["pattern"] as? String ?? "")"
        case "WebSearch": return "Search web: \(input["query"] as? String ?? "")"
        case "WebFetch":
            let host = URL(string: input["url"] as? String ?? "")?.host ?? ""
            return "Fetch \(host)"
        case "Agent", "Task": return "Agent: \(input["description"] as? String ?? "")"
        case "Skill": return "Skill: \(input["skill"] as? String ?? "")"
        case "AskUserQuestion": return "Ask a question"
        case "TodoWrite", "TaskCreate", "TaskUpdate": return "Update task list"
        default: return prettyToolName(name)
        }
    }
}
