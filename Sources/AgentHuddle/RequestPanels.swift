import SwiftUI

struct PermissionPanel: View {
    @EnvironmentObject var store: HuddleStore
    let request: PendingRequest
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.summary)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                PillButton(title: "Allow", primary: true) { store.allow(request) }
                PillButton(title: "Deny") { store.deny(request) }
                PillButton(title: "In \(Jumper.hostAppName(pid: session.pid))") { store.handOff(request, session: session) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.huddleInset))
    }
}

struct QuestionPanel: View {
    @EnvironmentObject var store: HuddleStore
    let request: PendingRequest
    let session: AgentSession
    @State private var picks: [String: Set<String>] = [:]
    @State private var other: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(request.questions, id: \.self) { question in
                questionView(question)
            }
            HStack(spacing: 8) {
                PillButton(title: "Send", primary: true) { send() }
                    .disabled(!complete)
                    .opacity(complete ? 1 : 0.5)
                PillButton(title: "Type in \(Jumper.hostAppName(pid: session.pid))") { store.handOff(request, session: session) }
            }
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
            ForEach(question.options, id: \.self) { option in
                optionRow(question, option)
            }
            TextField("Other answer…", text: Binding(
                get: { other[question.text] ?? "" },
                set: { other[question.text] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        }
    }

    private func optionRow(_ question: Question, _ option: QuestionOption) -> some View {
        let selected = picks[question.text]?.contains(option.label) ?? false
        return Button {
            toggle(question, option.label)
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

    private func toggle(_ question: Question, _ label: String) {
        var current = picks[question.text] ?? []
        if question.multiSelect {
            if current.contains(label) { current.remove(label) } else { current.insert(label) }
        } else {
            current = [label]
            other[question.text] = ""
        }
        picks[question.text] = current
    }

    private func answer(for question: Question) -> String? {
        let typed = (other[question.text] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = question.options.map(\.label).filter { picks[question.text]?.contains($0) ?? false }
        if question.multiSelect {
            let all = chosen + (typed.isEmpty ? [] : [typed])
            return all.isEmpty ? nil : all.joined(separator: ", ")
        }
        if !typed.isEmpty { return typed }
        return chosen.first
    }

    private var complete: Bool {
        request.questions.allSatisfy { answer(for: $0) != nil }
    }

    private func send() {
        var answers: [String: String] = [:]
        for question in request.questions {
            if let value = answer(for: question) { answers[question.text] = value }
        }
        store.answer(request, answers: answers)
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
