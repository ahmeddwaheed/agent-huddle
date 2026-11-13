import SwiftUI

extension Color {
    static let huddleBackground = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let huddleCard = Color.white.opacity(0.055)
    static let huddleCardHover = Color.white.opacity(0.085)
    static let huddleInset = Color.black.opacity(0.22)
    static let huddleStroke = Color.white.opacity(0.07)
    static let huddleLime = Color(red: 0.84, green: 0.95, blue: 0.40)
    static let huddleDim = Color.white.opacity(0.55)
    static let huddleFaint = Color.white.opacity(0.32)

    static let robotPalette: [Color] = [
        Color(red: 0.36, green: 0.55, blue: 0.98),
        Color(red: 0.95, green: 0.50, blue: 0.66),
        Color(red: 0.98, green: 0.66, blue: 0.36),
        Color(red: 0.62, green: 0.48, blue: 0.92),
        Color(red: 0.38, green: 0.80, blue: 0.58),
        Color(red: 0.33, green: 0.78, blue: 0.86),
    ]

    static func robot(for id: String) -> Color {
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return robotPalette[hash % robotPalette.count]
    }
}

struct RobotAvatar: View {
    let color: Color
    var size: CGFloat = 28
    var active = false
    var dim = false

    var body: some View {
        let w = size
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.2, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(1), color.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.9, height: w)
                VStack(spacing: w * 0.12) {
                    HStack(spacing: w * 0.24) { eye; eye }
                    Capsule().frame(width: w * 0.26, height: max(1.5, w * 0.06))
                }
                .foregroundStyle(Color.black.opacity(0.75))
            }
            HStack(spacing: w * 0.28) { leg; leg }
        }
        .phaseAnimator(active ? [0, -2] : [0]) { content, phase in
            content.offset(y: phase)
        } animation: { _ in .easeInOut(duration: 0.5) }
        .background(alignment: .bottom) {
            Ellipse().fill(Color.black.opacity(0.35))
                .frame(width: w * 0.75, height: w * 0.1)
                .blur(radius: 1)
                .offset(y: w * 0.12)
        }
        .saturation(dim ? 0.3 : 1)
        .opacity(dim ? 0.55 : 1)
        .frame(width: w + 2, height: w * 1.35)
    }

    private var eye: some View {
        RoundedRectangle(cornerRadius: size * 0.03).frame(width: size * 0.1, height: size * 0.16)
    }

    private var leg: some View {
        RoundedRectangle(cornerRadius: 1).fill(color.opacity(0.85)).frame(width: size * 0.1, height: size * 0.14)
    }
}

struct MiniRobot: View {
    let color: Color
    var selected = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color).frame(width: 22, height: 16)
            HStack(spacing: 4) {
                Capsule().frame(width: 2.5, height: 5)
                Capsule().frame(width: 2.5, height: 5)
            }
            .foregroundStyle(Color.black.opacity(0.75))
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(selected ? Color.white.opacity(0.9) : .clear, lineWidth: 1.5))
        .opacity(selected ? 1 : 0.75)
    }
}

struct ProgressRow: View {
    let session: AgentSession
    var large = false

    var body: some View {
        HStack(spacing: 8) {
            if !session.todos.isEmpty {
                ProgressBar(fraction: Double(session.completedTodos) / Double(max(session.todos.count, 1)))
                label(count: "\(session.completedTodos)/\(session.todos.count)", word: "tasks")
            } else {
                if session.isBusy { IndeterminateBar() } else { ProgressBar(fraction: 1, muted: true) }
                label(count: "\(session.steps.filter(\.done).count)", word: "steps")
            }
        }
    }

    private func label(count: String, word: String) -> some View {
        HStack(spacing: 3) {
            Text(count).foregroundStyle(Color.huddleLime).monospacedDigit()
            Text(word).foregroundStyle(Color.huddleFaint)
        }
        .font(.system(size: large ? 12 : 11, weight: .medium))
        .fixedSize()
    }
}

struct ProgressBar: View {
    let fraction: Double
    var muted = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(muted ? Color.white.opacity(0.25) : Color.huddleLime)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

struct IndeterminateBar: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(Color.huddleLime)
                    .frame(width: geo.size.width * 0.3)
                    .phaseAnimator([0, 1]) { content, phase in
                        content.offset(x: geo.size.width * 0.7 * phase)
                    } animation: { _ in .easeInOut(duration: 1.1) }
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(hovering ? 0.95 : 0.6))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct PillButton: View {
    let title: String
    var primary = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: primary ? .semibold : .medium))
                .foregroundStyle(primary ? Color.black.opacity(0.85) : Color.white.opacity(0.9))
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(primary ? Color.huddleLime.opacity(hovering ? 0.9 : 1) : Color.white.opacity(hovering ? 0.16 : 0.1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

func stepSymbol(_ kind: StepKind) -> String {
    switch kind {
    case .terminal: return "terminal"
    case .edit: return "pencil"
    case .read: return "doc.text"
    case .search: return "magnifyingglass"
    case .web: return "globe"
    case .agent: return "person.2"
    case .other: return "wrench.and.screwdriver"
    }
}
