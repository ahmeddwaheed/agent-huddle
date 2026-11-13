import SwiftUI

struct HuddleRoot: View {
    @EnvironmentObject var store: HuddleStore
    @State private var contentHeight: CGFloat = 200

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
        .frame(width: 400)
        .background(Color.huddleBackground)
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    private func scroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: HeightKey.self, value: geo.size.height)
                })
        }
        .scrollIndicators(.never)
        .frame(height: min(contentHeight, 620))
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
        HStack(spacing: 4) {
            IconButton(symbol: store.soundOn ? "speaker.wave.2" : "speaker.slash") { store.soundOn.toggle() }
            IconButton(symbol: store.compact ? "chevron.down" : "chevron.up") { store.compact.toggle() }
            IconButton(symbol: "xmark") { store.closePopover() }
        }
    }
}

struct ListHeader: View {
    @EnvironmentObject var store: HuddleStore

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(store.anyBusy ? Color.huddleLime : Color.white.opacity(0.3)).frame(width: 9, height: 9)
            Text("Agent Huddle").font(.system(size: 19, weight: .bold))
            Text("\(store.visibleSessions.count)").font(.system(size: 19, weight: .bold)).foregroundStyle(Color.huddleDim)
            Spacer()
            HeaderControls()
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

struct SessionList: View {
    @EnvironmentObject var store: HuddleStore

    var body: some View {
        VStack(spacing: 10) {
            if store.visibleSessions.isEmpty {
                Text("No agents are running.")
                    .foregroundStyle(Color.huddleDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            }
            ForEach(store.recentSessions) { session in
                SessionCard(session: session, pending: store.pendingRequest(for: session.id))
            }
            let older = store.olderDoneSessions
            if !older.isEmpty {
                Button {
                    store.showOlderDone.toggle()
                } label: {
                    HStack(spacing: 8) {
                        HStack(spacing: -6) {
                            ForEach(older.prefix(4)) { session in
                                MiniRobot(color: .robot(for: session.id)).scaleEffect(0.7).opacity(0.6)
                            }
                        }
                        Text("\(older.count) done earlier")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.huddleDim)
                        Spacer()
                        Image(systemName: store.showOlderDone ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.huddleDim)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.huddleCard.opacity(0.6)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if store.showOlderDone {
                    ForEach(older) { session in
                        SessionCard(session: session, pending: nil)
                    }
                }
            }
        }
    }
}

struct SessionCard: View {
    @EnvironmentObject var store: HuddleStore
    let session: AgentSession
    let pending: PendingRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                RobotAvatar(color: .robot(for: session.id), size: 40, active: session.isBusy, dim: !session.isBusy && pending == nil)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.displayTitle)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13, weight: pending == nil ? .regular : .semibold))
                        .foregroundStyle(pending == nil ? Color.huddleDim : Color.huddleLime)
                        .lineLimit(1)
                    if !store.compact {
                        ProgressRow(session: session).padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    IconButton(symbol: "arrow.up.forward.square") { store.jump(to: session) }
                    IconButton(symbol: "xmark") { store.dismiss(session) }
                }
            }
            if let pending {
                RequestPanel(request: pending, session: session)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.huddleCard))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(pending == nil ? .clear : Color.huddleLime, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { store.selectedId = session.id }
    }

    private var subtitle: String { sessionSubtitle(session, pending: pending) }
}

func sessionSubtitle(_ session: AgentSession, pending: PendingRequest?) -> String {
    if let pending { return pending.isQuestion ? "asks a question" : "needs permission" }
    if !session.isBusy { return "Done · waiting for you" }
    if let todo = session.activeTodo { return todo.activeForm ?? todo.title }
    if let step = session.runningStep { return step.label }
    return "Thinking…"
}

struct DetailHeader: View {
    @EnvironmentObject var store: HuddleStore
    let session: AgentSession

    var body: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "chevron.left", size: 16) { store.selectedId = nil }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.visibleSessions) { other in
                        MiniRobot(color: .robot(for: other.id), selected: other.id == session.id)
                            .onTapGesture { store.selectedId = other.id }
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.never)
            Spacer()
            IconButton(symbol: "arrow.up.forward.square") { store.jump(to: session) }
            HeaderControls()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

struct DetailView: View {
    @EnvironmentObject var store: HuddleStore
    let session: AgentSession

    var body: some View {
        let pending = store.pendingRequest(for: session.id)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                RobotAvatar(color: .robot(for: session.id), size: 52, active: session.isBusy)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle).font(.system(size: 19, weight: .bold)).lineLimit(2)
                    Text(sessionSubtitle(session, pending: pending))
                        .font(.system(size: 14))
                        .foregroundStyle(pending == nil ? Color.huddleDim : Color.huddleLime)
                    ProgressRow(session: session, large: true).padding(.top, 4)
                }
            }
            Divider().overlay(Color.white.opacity(0.15))

            if let pending {
                RequestPanel(request: pending, session: session)
            }

            if !store.compact, !session.todos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.todos, id: \.id) { todo in
                        HStack(spacing: 10) {
                            Image(systemName: todoSymbol(todo.status))
                                .foregroundStyle(todo.status == "in_progress" ? Color.huddleLime : Color.white.opacity(0.5))
                            Text(todo.title)
                                .font(.system(size: 13))
                                .foregroundStyle(todo.status == "completed" ? Color.huddleDim : Color.white)
                                .lineLimit(1)
                        }
                    }
                }
                Divider().overlay(Color.white.opacity(0.15))
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(session.steps.suffix(store.compact ? 4 : 10)) { step in
                    StepRow(step: step, running: session.runningStep?.id == step.id)
                }
                if session.steps.isEmpty {
                    Text("No steps yet.").foregroundStyle(Color.huddleDim)
                }
            }

            if let terminal = session.terminal, !store.compact {
                TerminalBox(snapshot: terminal)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.huddleCard))
    }

    private func todoSymbol(_ status: String) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "circle.dotted"
        default: return "circle"
        }
    }
}

struct StepRow: View {
    let step: Step
    let running: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if running {
                    ProgressView().controlSize(.small).tint(Color.huddleLime)
                } else if step.failed {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.red.opacity(0.8))
                } else if step.done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.white.opacity(0.45))
                } else {
                    Image(systemName: "circle").foregroundStyle(Color.white.opacity(0.3))
                }
            }
            .font(.system(size: 17))
            .frame(width: 20)
            Image(systemName: stepSymbol(step.kind))
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.65))
                .frame(width: 18)
            Text(step.label)
                .font(.system(size: 14, weight: running ? .semibold : .regular))
                .foregroundStyle(running ? Color.white : Color.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct TerminalBox: View {
    let snapshot: TerminalSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Terminal", systemImage: "apple.terminal")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            Text("$ " + snapshot.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.huddleLime)
                .lineLimit(3)
            if !snapshot.output.isEmpty {
                Text(snapshot.output)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(6)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.45)))
    }
}
