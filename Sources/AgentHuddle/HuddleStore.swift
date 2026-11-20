import AppKit
import SwiftUI
import Foundation

@MainActor
final class HuddleStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var pending: [PendingRequest] = []
    @Published var selectedId: String?
    @Published var compact = false
    @Published var showOlderDone = false
    @Published var picks: [String: [String: Set<String>]] = [:]
    @Published var otherAnswers: [String: [String: String]] = [:]
    @Published var denyNotes: [String: String] = [:]
    @Published private var focusedRequestIds: [String: String] = [:]
    private var colorIndex: [String: Int] = [:]
    @Published var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: "soundOn") }
    }

    var closePopover: () -> Void = {}
    var onNewRequest: (PendingRequest) -> Void = { _ in }

    private let huddleDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/huddle")
    private var pendingDir: URL { huddleDir.appendingPathComponent("pending") }
    private var responsesDir: URL { huddleDir.appendingPathComponent("responses") }
    private var heartbeatURL: URL { huddleDir.appendingPathComponent("app.heartbeat") }

    private let scanner = SessionScanner()
    private let scanQueue = DispatchQueue(label: "agent-huddle.scan", qos: .utility)
    private var scanInFlight = false
    private var dismissed: [String: Double]
    private var answeredIds = Set<String>()
    private var knownPendingIds = Set<String>()
    private var previousBusy: [String: Bool] = [:]
    private var timer: Timer?

    init() {
        soundOn = UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true
        dismissed = UserDefaults.standard.dictionary(forKey: "dismissed") as? [String: Double] ?? [:]
        if Demo.mode != nil {
            dismissed = [:]
            sessions = Demo.sessions()
            assignColors()
            pending = Demo.pending()
            return
        }
        let privateDir: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        for dir in [huddleDir, pendingDir, responsesDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: privateDir)
            try? FileManager.default.setAttributes(privateDir, ofItemAtPath: dir.path)
        }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var visibleSessions: [AgentSession] {
        sessions.filter { isVisible($0) }.sorted { a, b in
            let pa = pendingRequest(for: a.id) != nil, pb = pendingRequest(for: b.id) != nil
            if pa != pb { return pa }
            if a.isBusy != b.isBusy { return a.isBusy }
            return a.startedAt < b.startedAt
        }
    }

    var recentSessions: [AgentSession] { visibleSessions.filter { !isOlderDone($0) } }
    var olderDoneSessions: [AgentSession] { visibleSessions.filter { isOlderDone($0) } }

    var activeRequest: PendingRequest? {
        if let selectedId { return pendingRequest(for: selectedId) }
        return visibleSessions.lazy.compactMap { self.pendingRequest(for: $0.id) }.first
    }

    var needsAttention: Bool { !pending.isEmpty }
    var anyBusy: Bool { visibleSessions.contains { $0.isBusy } }

    func robotColor(_ sessionId: String) -> Color {
        guard let index = colorIndex[sessionId] else { return .robot(for: sessionId) }
        return Color.robotPalette[index]
    }

    private func assignColors() {
        let live = recentSessions
        let liveIds = Set(live.map(\.id))
        colorIndex = colorIndex.filter { liveIds.contains($0.key) }
        for session in live.sorted(by: { $0.startedAt < $1.startedAt }) where colorIndex[session.id] == nil {
            let used = Set(colorIndex.values)
            let hashed = Color.robotIndex(for: session.id)
            let free = Color.robotPalette.indices.first { !used.contains(($0 + hashed) % Color.robotPalette.count) }
            colorIndex[session.id] = free.map { ($0 + hashed) % Color.robotPalette.count } ?? hashed
        }
    }

    func pendingRequests(for sessionId: String) -> [PendingRequest] {
        pending.filter { $0.sessionId == sessionId }
    }

    func pendingRequest(for sessionId: String) -> PendingRequest? {
        let queue = pendingRequests(for: sessionId)
        if let focused = focusedRequestIds[sessionId], let match = queue.first(where: { $0.id == focused }) {
            return match
        }
        return queue.first
    }

    func queuePosition(of request: PendingRequest) -> (index: Int, count: Int) {
        let queue = pendingRequests(for: request.sessionId)
        return ((queue.firstIndex { $0.id == request.id } ?? 0) + 1, queue.count)
    }

    func moveInQueue(sessionId: String, by delta: Int) {
        let queue = pendingRequests(for: sessionId)
        guard queue.count > 1, let current = pendingRequest(for: sessionId),
              let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        let next = (index + delta + queue.count) % queue.count
        focusedRequestIds[sessionId] = queue[next].id
    }

    func session(_ id: String?) -> AgentSession? {
        sessions.first { $0.id == id }
    }

    func dismiss(_ session: AgentSession) {
        dismissed[session.id] = Date().timeIntervalSince1970
        UserDefaults.standard.set(dismissed, forKey: "dismissed")
        if selectedId == session.id { selectedId = nil }
        objectWillChange.send()
    }

    func jump(to session: AgentSession) {
        Jumper.activate(pid: session.pid)
        closePopover()
    }

    func allow(_ request: PendingRequest) {
        respond(request, ["behavior": "allow"])
    }

    func alwaysAllow(_ request: PendingRequest) {
        guard !request.suggestions.isEmpty else { return allow(request) }
        respond(request, ["behavior": "allow", "updatedPermissions": request.suggestions])
    }

    func deny(_ request: PendingRequest) {
        let note = (denyNotes[request.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let message = note.isEmpty ? "The user denied this in Agent Huddle." : "The user denied this. Their note: \(note)"
        respond(request, ["behavior": "deny", "message": message])
    }

    func toggleOption(_ request: PendingRequest, _ question: Question, _ label: String) {
        var current = picks[request.id]?[question.text] ?? []
        if question.multiSelect {
            if current.contains(label) { current.remove(label) } else { current.insert(label) }
        } else {
            current = [label]
            otherAnswers[request.id, default: [:]][question.text] = ""
        }
        picks[request.id, default: [:]][question.text] = current
    }

    func isPicked(_ request: PendingRequest, _ question: Question, _ label: String) -> Bool {
        picks[request.id]?[question.text]?.contains(label) ?? false
    }

    func answerText(_ request: PendingRequest, _ question: Question) -> String? {
        let typed = (otherAnswers[request.id]?[question.text] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = question.options.map(\.label).filter { isPicked(request, question, $0) }
        if question.multiSelect {
            let all = chosen + (typed.isEmpty ? [] : [typed])
            return all.isEmpty ? nil : all.joined(separator: ", ")
        }
        return typed.isEmpty ? chosen.first : typed
    }

    func canSend(_ request: PendingRequest) -> Bool {
        request.questions.allSatisfy { answerText(request, $0) != nil }
    }

    func sendAnswers(_ request: PendingRequest) {
        guard canSend(request) else { return }
        var answers: [String: String] = [:]
        for question in request.questions {
            answers[question.text] = answerText(request, question)
        }
        var input = request.rawInput
        input["answers"] = answers
        respond(request, ["behavior": "allow", "updatedInput": input])
    }

    func handleKey(_ key: String) -> Bool {
        guard let request = activeRequest else { return false }
        switch key {
        case "left":
            moveInQueue(sessionId: request.sessionId, by: -1)
        case "right":
            moveInQueue(sessionId: request.sessionId, by: 1)
        case "return":
            if request.isQuestion { sendAnswers(request) } else { allow(request) }
        case "a" where !request.isQuestion:
            alwaysAllow(request)
        case "d" where !request.isQuestion:
            deny(request)
        default:
            guard request.isQuestion, let number = Int(key), number >= 1 else { return false }
            let questions = request.questions
            guard let question = questions.first(where: { answerText(request, $0) == nil }) ?? questions.first,
                  number <= question.options.count else { return false }
            toggleOption(request, question, question.options[number - 1].label)
        }
        return true
    }

    func handOff(_ request: PendingRequest, session: AgentSession) {
        respond(request, ["behavior": "ask"])
        jump(to: session)
    }

    private func respond(_ request: PendingRequest, _ payload: [String: Any]) {
        let url = responsesDir.appendingPathComponent("\(request.id).json")
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: url, options: .atomic)
        answeredIds.insert(request.id)
        pending.removeAll { $0.id == request.id }
        picks[request.id] = nil
        otherAnswers[request.id] = nil
        denyNotes[request.id] = nil
    }

    private func isOlderDone(_ session: AgentSession) -> Bool {
        guard !session.isBusy, pendingRequest(for: session.id) == nil else { return false }
        return Date().timeIntervalSince1970 - session.statusUpdatedAt / 1000 > 3600
    }

    private func isVisible(_ session: AgentSession) -> Bool {
        guard let dismissedAt = dismissed[session.id] else { return true }
        if pendingRequest(for: session.id) != nil { return true }
        return session.isBusy && session.statusUpdatedAt / 1000 > dismissedAt
    }

    private func tick() {
        writeHeartbeat()
        loadSessions()
        loadPending()
    }

    private func writeHeartbeat() {
        let stamp = Data(String(Date().timeIntervalSince1970).utf8)
        try? stamp.write(to: heartbeatURL, options: .atomic)
    }

    private func loadSessions() {
        guard !scanInFlight else { return }
        scanInFlight = true
        let scanner = self.scanner
        scanQueue.async {
            let result = scanner.scan()
            DispatchQueue.main.async { [weak self] in
                self?.apply(result)
                self?.scanInFlight = false
            }
        }
    }

    private func apply(_ result: [AgentSession]) {
        for session in result {
            if previousBusy[session.id] == true, !session.isBusy, isVisible(session) {
                play("Tink")
            }
            previousBusy[session.id] = session.isBusy
        }
        sessions = result
        assignColors()
    }

    private func loadPending() {
        let files = (try? FileManager.default.contentsOfDirectory(at: pendingDir, includingPropertiesForKeys: nil)) ?? []
        var result: [PendingRequest] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = obj["id"] as? String,
                  !answeredIds.contains(id)
            else { continue }
            let hookPid = (obj["hookPid"] as? NSNumber)?.int32Value ?? 0
            if hookPid > 0, !processAlive(hookPid) {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            result.append(PendingRequest(
                id: id,
                sessionId: obj["sessionId"] as? String ?? "",
                toolName: obj["toolName"] as? String ?? "",
                rawInput: obj["toolInput"] as? [String: Any] ?? [:],
                createdAt: (obj["createdAt"] as? NSNumber)?.doubleValue ?? 0,
                hookPid: hookPid,
                suggestions: obj["suggestions"] as? [[String: Any]] ?? [],
                agentType: obj["agentType"] as? String
            ))
        }
        result.sort { $0.createdAt < $1.createdAt }

        let newRequests = result.filter { !knownPendingIds.contains($0.id) }
        if let newest = newRequests.last {
            play("Glass")
            onNewRequest(newest)
        }
        knownPendingIds = Set(result.map(\.id))
        focusedRequestIds = focusedRequestIds.filter { knownPendingIds.contains($0.value) }
        answeredIds.formIntersection(knownPendingIds)
        pending = result
    }

    private func play(_ name: String) {
        guard soundOn else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

final class SessionScanner: @unchecked Sendable {
    private let claudeDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    private var readers: [String: TranscriptReader] = [:]

    func scan() -> [AgentSession] {
        let dir = claudeDir.appendingPathComponent("sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var result: [AgentSession] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = obj["sessionId"] as? String,
                  let pid = (obj["pid"] as? NSNumber)?.int32Value,
                  !(obj["entrypoint"] as? String ?? "").hasPrefix("sdk"),
                  processAlive(pid)
            else { continue }

            var session = AgentSession(
                id: id,
                pid: pid,
                cwd: obj["cwd"] as? String ?? "",
                startedAt: (obj["startedAt"] as? NSNumber)?.doubleValue ?? 0,
                name: obj["name"] as? String ?? "",
                status: obj["status"] as? String ?? "idle",
                statusUpdatedAt: (obj["statusUpdatedAt"] as? NSNumber)?.doubleValue ?? 0
            )
            if let reader = reader(for: session) {
                reader.refresh()
                session.title = reader.title
                session.steps = reader.steps
                session.todos = reader.todos
                session.terminal = reader.terminal
            }
            result.append(session)
        }
        let liveIds = Set(result.map(\.id))
        readers = readers.filter { liveIds.contains($0.key) }
        return result
    }

    private func reader(for session: AgentSession) -> TranscriptReader? {
        if let existing = readers[session.id] { return existing }
        let projects = claudeDir.appendingPathComponent("projects")
        let encoded = String(session.cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        var url = projects.appendingPathComponent(encoded).appendingPathComponent("\(session.id).jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            let folders = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
            guard let match = folders
                .map({ $0.appendingPathComponent("\(session.id).jsonl") })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) })
            else { return nil }
            url = match
        }
        let reader = TranscriptReader(url: url)
        readers[session.id] = reader
        return reader
    }
}

func processAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}
