import SwiftUI

struct HuddleRoot: View {
    @EnvironmentObject var store: HuddleStore
    @State private var contentHeight: CGFloat = 200
    var solidBackground = false

    var body: some View {
        VStack(spacing: 0) {
            if let session = store.session(store.selectedId) {
                DetailHeader(session: session)
                scroll { DetailView(session: session) }
            } else {
                ListHeader()
                scroll { SessionList() }
            }
        }
        .frame(width: 340)
        .background(solidBackground ? Color.huddleBackground : Color.clear)
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    private func scroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: HeightKey.self, value: geo.size.height)
                })
        }
        .scrollIndicators(.never)
        .frame(height: min(contentHeight, 520))
        .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct HeaderControls: View {
    @EnvironmentObject var store: HuddleStore

    var body: some View {
        HStack(spacing: 2) {
            IconButton(symbol: store.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", help: "Sound") { store.soundOn.toggle() }
            IconButton(symbol: store.compact ? "rectangle.expand.vertical" : "rectangle.compress.vertical", help: "Compact") { store.compact.toggle() }
            IconButton(symbol: "xmark", help: "Close (Esc)") { store.closePopover() }
        }
    }
}

struct ListHeader: View {
    @EnvironmentObject var store: HuddleStore

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(store.anyBusy ? Color.huddleLime : Color.white.opacity(0.3))
                .frame(width: 7, height: 7)
                .shadow(color: store.anyBusy ? Color.huddleLime.opacity(0.7) : .clear, radius: 3)
            Text("Agent Huddle").font(.system(size: 13, weight: .semibold))
            Text("\(store.recentSessions.count)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.huddleDim)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            Spacer()
            HeaderControls()
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
    }
}

struct SessionList: View {
    @EnvironmentObject var store: HuddleStore

    var body: some View {
        VStack(spacing: 6) {
            if store.visibleSessions.isEmpty {
                VStack(spacing: 6) {
                    RobotAvatar(color: .robot(for: "empty"), size: 30, dim: true)
                    Text("No agents are running")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.huddleDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            ForEach(store.recentSessions) { session in
                SessionCard(session: session, pending: store.pendingRequest(for: session.id))
            }
            let older = store.olderDoneSessions
            if !older.isEmpty {
                OlderDoneRow(older: older)
                if store.showOlderDone {
                    ForEach(older) { session in
                        SessionCard(session: session, pending: nil)
                    }
                }
            }
        }
    }
}

struct OlderDoneRow: View {
    @EnvironmentObject var store: HuddleStore
    let older: [AgentSession]
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { store.showOlderDone.toggle() }
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(older.prefix(4)) { session in
                        MiniRobot(color: store.robotColor(session.id)).scaleEffect(0.75)
                    }
                }
                Text("\(older.count) done earlier")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.huddleDim)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.huddleFaint)
                    .rotationEffect(.degrees(store.showOlderDone ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Color.huddleCard : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SessionCard: View {
    @EnvironmentObject var store: HuddleStore
    let session: AgentSession
    let pending: PendingRequest?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                RobotAvatar(color: store.robotColor(session.id), size: 26, active: session.isBusy, dim: !session.isBusy && pending == nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .padding(.trailing, hovering ? 44 : 0)
                    Text(sessionSubtitle(session, pending: pending, waiting: store.pendingRequests(for: session.id).count))
                        .font(.system(size: 11.5, weight: pending == nil ? .regular : .medium))
                        .foregroundStyle(pending == nil ? Color.huddleDim : Color.huddleLime)
                        .lineLimit(1)
                    if !store.compact {
                        ProgressRow(session: session).padding(.top, 4)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    IconButton(symbol: "arrow.up.forward", help: "Jump to session") { store.jump(to: session) }
                    IconButton(symbol: "xmark", help: "Cross off") { store.dismiss(session) }
                }
                .offset(x: 4, y: -4)
                .opacity(hovering ? 1 : 0)
            }
            if let pending {
                RequestPanel(request: pending, session: session)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? Color.huddleCardHover : Color.huddleCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(pending == nil ? Color.huddleStroke : Color.huddleLime.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: pending == nil ? .clear : Color.huddleLime.opacity(0.18), radius: 8)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { store.selectedId = session.id }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

func sessionSubtitle(_ session: AgentSession, pending: PendingRequest?, waiting: Int = 1) -> String {
    if waiting > 1 { return "\(waiting) requests waiting" }
    if let pending { return pending.isQuestion ? "Asks a question" : "Needs permission" }
    if !session.isBusy { return "Done · waiting for you" }
    if let todo = session.activeTodo { return todo.activeForm ?? todo.title }
    if let step = session.runningStep { return step.label }
    return "Thinking…"
}

struct DetailHeader: View {
    @EnvironmentObject var store: HuddleStore
    let session: AgentSession

    var body: some View {
        HStack(spacing: 6) {
            IconButton(symbol: "chevron.left", help: "Back") { store.selectedId = nil }
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(store.recentSessions) { other in
                        MiniRobot(color: store.robotColor(other.id), selected: other.id == session.id)
                            .onTapGesture { store.selectedId = other.id }
                    }
                }
                .padding(3)
            }
            .scrollIndicators(.never)
            Spacer()
            IconButton(symbol: "arrow.up.forward", help: "Jump to session") { store.jump(to: session) }
            HeaderControls()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

struct DetailView: View {
    @EnvironmentObject var store: HuddleStore
    let session: AgentSession

    var body: some View {
        let pending = store.pendingRequest(for: session.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RobotAvatar(color: store.robotColor(session.id), size: 34, active: session.isBusy)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    Text(sessionSubtitle(session, pending: pending, waiting: store.pendingRequests(for: session.id).count))
                        .font(.system(size: 12))
                        .foregroundStyle(pending == nil ? Color.huddleDim : Color.huddleLime)
                    ProgressRow(session: session, large: true).padding(.top, 5)
                }
            }

            if let pending {
                RequestPanel(request: pending, session: session)
            }

            if !store.compact, !session.todos.isEmpty {
                section("Tasks") {
                    ForEach(session.todos, id: \.id) { todo in
                        HStack(spacing: 8) {
                            Image(systemName: todoSymbol(todo.status))
                                .font(.system(size: 12))
                                .foregroundStyle(todo.status == "in_progress" ? Color.huddleLime : Color.huddleFaint)
                                .frame(width: 14)
                            Text(todo.title)
                                .font(.system(size: 12))
                                .foregroundStyle(todo.status == "completed" ? Color.huddleDim : Color.white)
                                .strikethrough(todo.status == "completed", color: Color.huddleFaint)
                                .lineLimit(1)
                        }
                    }
                }
            }

            section("Steps") {
                ForEach(session.steps.suffix(store.compact ? 4 : 8)) { step in
                    StepRow(step: step, running: session.runningStep?.id == step.id)
                }
                if session.steps.isEmpty {
                    Text("No steps yet").font(.system(size: 12)).foregroundStyle(Color.huddleDim)
                }
            }

            if let terminal = session.terminal, !store.compact {
                TerminalBox(snapshot: terminal)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.huddleCard))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.huddleStroke, lineWidth: 1))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.huddleFaint)
            content()
        }
    }

    private func todoSymbol(_ status: String) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "circle.dotted.circle"
        default: return "circle"
        }
    }
}

struct StepRow: View {
    let step: Step
    let running: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if running {
                    ProgressView().controlSize(.mini)
                } else if step.failed {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.red.opacity(0.85))
                } else if step.done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.huddleFaint)
                } else {
                    Image(systemName: "circle").foregroundStyle(Color.huddleFaint)
                }
            }
            .font(.system(size: 12))
            .frame(width: 14)
            Image(systemName: stepSymbol(step.kind))
                .font(.system(size: 10.5))
                .foregroundStyle(Color.huddleDim)
                .frame(width: 14)
            Text(step.label)
                .font(.system(size: 12, weight: running ? .medium : .regular))
                .foregroundStyle(running ? Color.white : Color.white.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct TerminalBox: View {
    let snapshot: TerminalSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("$ " + snapshot.command)
                .foregroundStyle(Color.huddleLime)
                .lineLimit(2)
            if !snapshot.output.isEmpty {
                Text(snapshot.output)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(5)
            }
        }
        .font(.system(size: 10.5, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.huddleInset))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .foregroundStyle(Color.huddleFaint)
                .padding(8)
        }
    }
}
