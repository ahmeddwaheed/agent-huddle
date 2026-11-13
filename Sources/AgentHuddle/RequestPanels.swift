import SwiftUI

struct PermissionPanel: View {
    @EnvironmentObject var store: HuddleStore
    let request: PendingRequest
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.summary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.huddleInset))
            HStack(spacing: 6) {
                PillButton(title: "Allow", primary: true) { store.allow(request) }
                if request.alwaysAllowLabel != nil {
                    PillButton(title: "Always") { store.alwaysAllow(request) }
                }
                PillButton(title: "Deny") { store.deny(request) }
                PillButton(title: "In \(Jumper.hostAppName(pid: session.pid))") { store.handOff(request, session: session) }
            }
            if let label = request.alwaysAllowLabel {
                Text("Always allows \(label)")
                    .font(.system(size: 10.5))
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
    }
}

struct QuestionPanel: View {
    @EnvironmentObject var store: HuddleStore
    let request: PendingRequest
    let session: AgentSession

    var body: some View {
        let ready = store.canSend(request)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(request.questions, id: \.self) { question in
                questionView(question)
            }
            HStack(spacing: 6) {
                PillButton(title: "Send", primary: true) { store.sendAnswers(request) }
                    .disabled(!ready)
                    .opacity(ready ? 1 : 0.5)
                PillButton(title: "Type in \(Jumper.hostAppName(pid: session.pid))") { store.handOff(request, session: session) }
            }
            KeyHints(hints: ["1–\(min(request.questions.first?.options.count ?? 1, 9)) Pick", "↩ Send", "Esc Close"])
        }
    }

    @ViewBuilder
    private func questionView(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header = question.header, !header.isEmpty {
                Text(header.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.huddleLime))
            }
            Text(question.text)
                .font(.system(size: 13, weight: .semibold))
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
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: indicator(question.multiSelect, selected))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color.huddleLime : Color.huddleFaint)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(.system(size: 12, weight: .medium))
                    if let detail = option.detail, !detail.isEmpty {
                        Text(detail).font(.system(size: 11)).foregroundStyle(Color.huddleDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if number <= 9 {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.huddleFaint)
                        .frame(width: 16, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.huddleLime.opacity(0.1) : Color.huddleInset))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? Color.huddleLime.opacity(0.8) : .clear, lineWidth: 1))
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
                    .foregroundStyle(Color.huddleFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = true }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.huddleInset))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.huddleStroke))
    }
}

struct KeyHints: View {
    let hints: [String]

    var body: some View {
        Text(hints.joined(separator: "   "))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.28))
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
