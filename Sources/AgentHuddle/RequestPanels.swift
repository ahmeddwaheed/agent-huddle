import SwiftUI

struct PermissionPanel: View {
    @EnvironmentObject var store: HuddleStore
    let request: PendingRequest
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.summary)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                PillButton(title: "Allow", primary: true) { store.allow(request) }
                if request.alwaysAllowLabel != nil {
                    PillButton(title: "Always") { store.alwaysAllow(request) }
                }
                PillButton(title: "Deny") { store.deny(request) }
                PillButton(title: "In \(Jumper.hostAppName(pid: session.pid))") { store.handOff(request, session: session) }
            }
            if let label = request.alwaysAllowLabel {
                Text("Always allows \(label)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.huddleDim)
                    .lineLimit(2)
            }
            NoteField(placeholder: "Optional: tell Claude why you deny", text: Binding(
                get: { store.denyNotes[request.id] ?? "" },
                set: { store.denyNotes[request.id] = $0 }
            )) { store.deny(request) }
            KeyHints(hints: request.alwaysAllowLabel == nil
                     ? ["↩ Allow", "D Deny", "Esc Close"]
                     : ["↩ Allow", "A Always", "D Deny", "Esc Close"])
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.huddleInset))
    }
}

struct QuestionPanel: View {
    @EnvironmentObject var store: HuddleStore
    let request: PendingRequest
    let session: AgentSession

    var body: some View {
        let ready = store.canSend(request)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(request.questions, id: \.self) { question in
                questionView(question)
            }
            HStack(spacing: 8) {
                PillButton(title: "Send", primary: true) { store.sendAnswers(request) }
                    .disabled(!ready)
                    .opacity(ready ? 1 : 0.5)
                PillButton(title: "Type in \(Jumper.hostAppName(pid: session.pid))") { store.handOff(request, session: session) }
            }
            KeyHints(hints: ["1–\(min(request.questions.first?.options.count ?? 1, 9)) Pick", "↩ Send", "Esc Close"])
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.huddleInset))
    }

    @ViewBuilder
    private func questionView(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = question.header, !header.isEmpty {
                Text(header.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.huddleLime))
            }
            Text(question.text)
                .font(.system(size: 15, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(question.options.enumerated()), id: \.element) { index, option in
                optionRow(question, option, number: index + 1)
            }
            NoteField(placeholder: "Other answer…", text: Binding(
                get: { store.otherAnswers[request.id]?[question.text] ?? "" },
                set: { store.otherAnswers[request.id, default: [:]][question.text] = $0 }
            )) { store.sendAnswers(request) }
        }
    }

    private func optionRow(_ question: Question, _ option: QuestionOption, number: Int) -> some View {
        let selected = store.isPicked(request, question, option.label)
        return Button {
            store.toggleOption(request, question, option.label)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: indicator(question.multiSelect, selected))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(selected ? Color.huddleLime : Color.white.opacity(0.5))
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(.system(size: 14, weight: .medium))
                    if let detail = option.detail, !detail.isEmpty {
                        Text(detail).font(.system(size: 12)).foregroundStyle(Color.huddleDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if number <= 9 {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.huddleLime : .clear, lineWidth: 1.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func indicator(_ multi: Bool, _ selected: Bool) -> String {
        if multi { return selected ? "checkmark.square.fill" : "square" }
        return selected ? "circle.fill" : "circle"
    }
}

struct NoteField: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing || !text.isEmpty {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(onSubmit)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused, text.isEmpty { editing = false }
                    }
                    .onAppear { focused = editing }
            } else {
                Text(placeholder)
                    .foregroundStyle(Color.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = true }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }
}

struct KeyHints: View {
    let hints: [String]

    var body: some View {
        Text(hints.joined(separator: "  ·  "))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.35))
    }
}

struct RequestPanel: View {
    let request: PendingRequest
    let session: AgentSession

    var body: some View {
        if request.isQuestion {
            QuestionPanel(request: request, session: session)
        } else {
            PermissionPanel(request: request, session: session)
        }
    }
}
