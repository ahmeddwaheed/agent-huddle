import AppKit
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let store: HuddleStore
    private let openSession: (String) -> Void
    private var deliveredIds = Set<String>()
    private let center: UNUserNotificationCenter?

    private enum Action {
        static let allow = "allow"
        static let deny = "deny"
        static let permissionCategory = "permission"
        static let questionCategory = "question"
    }

    init(store: HuddleStore, openSession: @escaping (String) -> Void) {
        self.store = store
        self.openSession = openSession
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        guard let center else { return }
        center.delegate = self
        let allow = UNNotificationAction(identifier: Action.allow, title: "Allow")
        let deny = UNNotificationAction(identifier: Action.deny, title: "Deny", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Action.permissionCategory, actions: [allow, deny], intentIdentifiers: []),
            UNNotificationCategory(identifier: Action.questionCategory, actions: [], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func notify(_ request: PendingRequest) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = store.session(request.sessionId)?.displayTitle ?? "Claude Code"
        content.subtitle = request.isQuestion ? "Asks a question" : "Needs permission"
        content.body = request.isQuestion ? (request.questions.first?.text ?? "") : request.summary
        content.categoryIdentifier = request.isQuestion ? Action.questionCategory : Action.permissionCategory
        content.userInfo = ["requestId": request.id, "sessionId": request.sessionId]
        center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: nil))
        deliveredIds.insert(request.id)
    }

    func removeAnswered() {
        guard let center else { return }
        let gone = deliveredIds.subtracting(store.pending.map(\.id))
        guard !gone.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: Array(gone))
        deliveredIds.subtract(gone)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let requestId = info["requestId"] as? String ?? ""
        let sessionId = info["sessionId"] as? String ?? ""
        let action = response.actionIdentifier
        Task { @MainActor in
            self.handle(action: action, requestId: requestId, sessionId: sessionId)
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    private func handle(action: String, requestId: String, sessionId: String) {
        let request = store.pending.first { $0.id == requestId }
        switch action {
        case Action.allow:
            if let request { store.allow(request) }
        case Action.deny:
            if let request { store.deny(request) }
        default:
            openSession(sessionId)
        }
    }
}
