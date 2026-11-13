import SwiftUI

extension Color {
    static let huddleBackground = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let huddleCard = Color(red: 0.165, green: 0.165, blue: 0.175)
    static let huddleInset = Color(red: 0.23, green: 0.23, blue: 0.24)
    static let huddleLime = Color(red: 0.85, green: 0.96, blue: 0.36)
    static let huddleDim = Color.white.opacity(0.55)

    static let robotPalette: [Color] = [
        Color(red: 0.33, green: 0.52, blue: 0.96),
        Color(red: 0.93, green: 0.48, blue: 0.64),
        Color(red: 0.95, green: 0.64, blue: 0.35),
        Color(red: 0.49, green: 0.38, blue: 0.75),
        Color(red: 0.36, green: 0.78, blue: 0.56),
        Color(red: 0.30, green: 0.75, blue: 0.82),
    ]

    static func robot(for id: String) -> Color {
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return robotPalette[hash % robotPalette.count]
    }
}

struct RobotAvatar: View {
    let color: Color
    var size: CGFloat = 44
    var active = false
    var dim = false
    var showShadow = true

    var body: some View {
        let w = size
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.14).fill(color)
                    .frame(width: w * 0.92, height: w * 1.08)
                VStack(spacing: w * 0.13) {
                    HStack(spacing: w * 0.26) { eye; eye }
                    Capsule().frame(width: w * 0.28, height: max(2, w * 0.055))
                }
                .foregroundStyle(Color.black.opacity(0.78))
            }
            HStack(spacing: w * 0.3) { leg; leg }
        }
        .phaseAnimator(active ? [0, -3] : [0]) { content, phase in
            content.offset(y: phase)
        } animation: { _ in .easeInOut(duration: 0.45) }
        .background(alignment: .bottom) {
            if showShadow {
                Ellipse().fill(Color.black.opacity(0.45))
                    .frame(width: w * 0.85, height: w * 0.12)
                    .offset(y: w * 0.16)
            }
        }
        .opacity(dim ? 0.45 : 1)
        .frame(width: w + 4, height: w * 1.45)
    }

    private var eye: some View {
        RoundedRectangle(cornerRadius: size * 0.03).frame(width: size * 0.11, height: size * 0.17)
    }

    private var leg: some View {
        Rectangle().fill(color).frame(width: size * 0.11, height: size * 0.16)
    }
}

struct MiniRobot: View {
    let color: Color
    var selected = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(color).frame(width: 30, height: 22)
            HStack(spacing: 5) {
                Capsule().frame(width: 3, height: 7)
                Capsule().frame(width: 3, height: 7)
            }
            .foregroundStyle(Color.black.opacity(0.75))
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.white : .clear, lineWidth: 1.5).padding(-2))
    }
}

struct ProgressRow: View {
    let session: AgentSession
    var large = false

    var body: some View {
        if !session.todos.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text("\(session.completedTodos)/\(session.todos.count)")
                        .foregroundStyle(Color.huddleLime)
                    Text("Tasks").foregroundStyle(Color.white.opacity(0.75))
                }
                .font(.system(size: large ? 15 : 13, weight: .bold))
                ProgressBar(fraction: Double(session.completedTodos) / Double(max(session.todos.count, 1)))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text("\(session.steps.filter(\.done).count)")
                        .foregroundStyle(Color.huddleLime)
                    Text("steps").foregroundStyle(Color.white.opacity(0.75))
                }
                .font(.system(size: large ? 15 : 13, weight: .bold))
                if session.isBusy { IndeterminateBar() } else { ProgressBar(fraction: 1, muted: true) }
            }
        }
    }
}

struct ProgressBar: View {
    let fraction: Double
    var muted = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(muted ? Color.white.opacity(0.3) : Color.huddleLime)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

struct IndeterminateBar: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Color.huddleLime)
                    .frame(width: geo.size.width * 0.3)
                    .phaseAnimator([0, 1]) { content, phase in
                        content.offset(x: geo.size.width * 0.7 * phase)
                    } animation: { _ in .easeInOut(duration: 1.1) }
            }
            .clipShape(Capsule())
        }
        .frame(height: 5)
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primary ? Color.black : Color.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(primary ? Color.huddleLime : Color.white.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

func stepSymbol(_ kind: StepKind) -> String {
    switch kind {
    case .terminal: return "apple.terminal"
    case .edit: return "pencil"
    case .read: return "doc.text"
    case .search: return "magnifyingglass"
    case .web: return "globe"
    case .agent: return "person.2"
    case .other: return "wrench.and.screwdriver"
    }
}
