import AppKit
import Foundation

@MainActor
final class HuddleStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var pending: [PendingRequest] = []
    @Published var selectedId: String?
    @Published var compact = false
    @Published var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: "soundOn") }
    }

    var closePopover: () -> Void = {}

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
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)
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

    var needsAttention: Bool { !pending.isEmpty }
    var anyBusy: Bool { visibleSessions.contains { $0.isBusy } }

    func pendingRequest(for sessionId: String) -> PendingRequest? {
        pending.first { $0.sessionId == sessionId }
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

    func deny(_ request: PendingRequest) {
        respond(request, ["behavior": "deny", "message": "The user denied this in Agent Huddle."])
    }

    func answer(_ request: PendingRequest, answers: [String: String]) {
        var input = request.rawInput
        input["answers"] = answers
        respond(request, ["behavior": "allow", "updatedInput": input])
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
                hookPid: hookPid
            ))
        }
        result.sort { $0.createdAt < $1.createdAt }

        if !Set(result.map(\.id)).subtracting(knownPendingIds).isEmpty { play("Glass") }
        knownPendingIds = Set(result.map(\.id))
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
