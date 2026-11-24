import SwiftUI

// The ears sit on the black notch, so they always use the dark palette
private let ears = Theme.macchiato

struct IslandView: View {
    @ObservedObject var m: Model
    @Environment(\.colorScheme) var scheme
    var t: Theme { .current(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftEar.frame(maxWidth: .infinity)
                Color.clear.frame(width: m.geo.notch)
                rightEar.frame(maxWidth: .infinity)
            }
            .frame(minWidth: m.collapsedWidth, maxWidth: .infinity)
            .frame(height: m.geo.height)

            switch m.mode {
            case .collapsed:
                EmptyView()
            case .peek(let block):
                SwiftUI.Group { // HerdrMenu.swift has its own Group
                    if let r = m.requests.first(where: { $0.block == block }) {
                        RequestCard(r: r, m: m, t: t)
                    } else if let i = m.item(block) {
                        Card(t: t) { Row(i: i, m: m, t: t) }
                    }
                }
                .frame(width: m.panelWidth)
                .padding([.horizontal, .bottom], 8)
                .transition(.island)
            case .full:
                VStack(spacing: 8) {
                    ForEach(m.requests) { RequestCard(r: $0, m: m, t: t) }
                    Card(t: t) {
                        if m.items.isEmpty {
                            Text("No agents running in Rex").font(.system(size: 12)).foregroundStyle(t.subtext).frame(height: 44)
                        }
                        ForEach(m.sorted) { Row(i: $0, m: m, t: t) }
                    }
                }
                .frame(width: m.panelWidth)
                .padding([.horizontal, .bottom], 8)
                .transition(.island)
            }
        }
        .fixedSize()
        .background(.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: m.mode == .collapsed ? 10 : 22,
                                          bottomTrailingRadius: m.mode == .collapsed ? 10 : 22))
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { m.contentSize = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    @ViewBuilder var leftEar: some View {
        SwiftUI.Group { // HerdrMenu.swift has its own Group
            if !m.blocked.isEmpty || !m.requests.isEmpty {
                Image(systemName: "hand.raised.fill").foregroundStyle(ears.peach).accessibilityLabel("Needs you")
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.2)), isActive: true)
            } else if !m.unseen.isEmpty {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(ears.green).accessibilityLabel("Finished")
                    .symbolEffect(.bounce, value: m.unseen.count)
            } else if !m.working.isEmpty {
                Image(systemName: "sparkle").foregroundStyle(Theme.macchiato.accent).accessibilityLabel("Working")
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: true)
            } else if m.showEars {
                Image(systemName: "circle").foregroundStyle(ears.overlay).accessibilityLabel("Idle")
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder var rightEar: some View {
        let waiting = max(m.blocked.count, Set(m.requests.map(\.block)).count)
        let n = waiting > 0 ? waiting : !m.unseen.isEmpty ? m.unseen.count : m.working.count
        if n > 0 {
            Text("\(n)").font(.system(size: 11, weight: .semibold)).foregroundStyle(ears.text)
                .contentTransition(.numericText())
        }
    }
}

// Like the Dynamic Island: the content sharpens from a blur and grows from the top once the pill has started
// growing, and goes out faster than it came
struct Unfocused: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        content.blur(radius: on ? 8 : 0).opacity(on ? 0 : 1).scaleEffect(on ? 0.9 : 1, anchor: .top)
    }
}

extension AnyTransition {
    static let island = {
        let blur = AnyTransition.modifier(active: Unfocused(on: true), identity: Unfocused(on: false))
        return AnyTransition.asymmetric(insertion: blur.animation(spring.delay(0.03)), removal: blur.animation(.easeIn(duration: 0.1)))
    }()
}

struct Card<Content: View>: View {
    let t: Theme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(t.base, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct Row: View {
    let i: Item
    @ObservedObject var m: Model
    let t: Theme

    var subtitle: String {
        if let msg = i.msg, !msg.isEmpty { return msg }
        switch i.state {
        case "working": return m.activity[i.block] ?? "Working"
        case "blocked":
            if let r = m.requests.first(where: { $0.block == i.block }) { return "Wants to use \(r.tool)" }
            return ["permission": "Needs permission", "question": "Has a question", "auth": "Needs a password"][i.kind ?? ""] ?? "Needs you"
        case "done": return m.prompts[i.block].map { "You: \($0)" } ?? "Done"
        default: return i.state.capitalized
        }
    }

    var body: some View {
        Button { m.jump(i.block) } label: {
            HStack(spacing: 12) {
                Dot(color: t.color(for: i.state), pulsing: i.state == "working" || i.state == "blocked" || m.unseen.contains(i.block))
                VStack(alignment: .leading, spacing: 2) {
                    Text(i.label).font(.system(size: 13, weight: m.unseen.contains(i.block) ? .bold : .semibold))
                        .foregroundStyle(t.text)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(t.subtext).lineLimit(1)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(short(m.since[i.block])).font(.system(size: 11).monospacedDigit()).foregroundStyle(t.overlay)
                    }
                    // Which app it's in, once there are agents from both
                    if m.bothApps { Text(i.herdr == true ? "herdr" : "Rex").font(.system(size: 10)).foregroundStyle(t.overlay) }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(m.hoveredRow == i.block ? t.surface.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { m.hoveredRow = $0 ? i.block : nil }
    }

    func short(_ date: Date?) -> String {
        guard let date else { return "" }
        let s = Int(-date.timeIntervalSinceNow)
        return s < 60 ? "now" : s < 3600 ? "\(s / 60)m" : s < 86400 ? "\(s / 3600)h" : "\(s / 86400)d"
    }
}

/// A status dot; working and blocked ones send out a ripple every 1.4s
struct Dot: View {
    let color: Color
    let pulsing: Bool

    var body: some View {
        TimelineView(.animation(paused: !pulsing)) { context in
            let phase = pulsing ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4 : 1
            Circle().fill(color).frame(width: 8, height: 8)
                .background(Circle().stroke(color, lineWidth: 1.5).scaleEffect(1 + 1.6 * phase).opacity(0.9 * (1 - phase)))
        }
    }
}

struct RequestCard: View {
    let r: Request
    @ObservedObject var m: Model
    let t: Theme

    var isPlan: Bool { r.tool == "ExitPlanMode" }
    var file: String { ((r.input["file_path"] as? String ?? "") as NSString).lastPathComponent }
    var title: String {
        switch r.tool {
        case "ExitPlanMode": "Plan ready for review"
        case "Bash": "Run a command"
        case "Edit", "MultiEdit": "Edit \(file)"
        case "Write": "Create \(file)"
        default: "Use \(r.tool)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isPlan ? "list.bullet.clipboard.fill" : "exclamationmark.shield.fill").foregroundStyle(t.peach)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text).lineLimit(1)
                Spacer()
                Button(m.item(r.block)?.label ?? "") { m.jump(r.block) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(t.subtext)
            }
            preview
            HStack(spacing: 8) {
                Button(isPlan ? "Keep planning" : "Deny") { m.reply(r, allow: false) }
                    .buttonStyle(Pill(bg: t.surface, fg: t.text))
                if !isPlan, !r.suggestions.isEmpty {
                    Button("Always allow") { m.reply(r, allow: true, always: true) }
                        .buttonStyle(Pill(bg: t.surface, fg: t.text))
                }
                Button(isPlan ? "Approve plan" : "Allow") { m.reply(r, allow: true) }
                    .buttonStyle(Pill(bg: t.accent, fg: t.base))
            }
        }
        .padding(14)
        .background(t.base, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder var preview: some View {
        switch r.tool {
        case "ExitPlanMode":
            ScrollView { Markdown(text: r.input["plan"] as? String ?? "", t: t).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 340)
        case "Bash":
            Code(t: t, lines: [(" ", r.input["command"] as? String ?? "")])
        case "Edit":
            Code(t: t, lines: diff(r.input["old_string"], "-") + diff(r.input["new_string"], "+"))
        case "Write":
            Code(t: t, lines: diff(r.input["content"], "+"))
        default:
            let json = (try? JSONSerialization.data(withJSONObject: r.input, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            Code(t: t, lines: [(" ", String(decoding: json, as: UTF8.self))])
        }
    }

    func diff(_ text: Any?, _ sign: String) -> [(String, String)] {
        (text as? String ?? "").split(separator: "\n", omittingEmptySubsequences: false).map { (sign, String($0)) }
    }
}

/// Monospaced preview lines, tinted red or green for diffs, capped at 12 lines
struct Code: View {
    let t: Theme
    let lines: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.prefix(12).enumerated()), id: \.offset) { _, line in
                Text(line.0 == " " ? line.1 : "\(line.0) \(line.1)")
                    .lineLimit(line.0 == " " ? 8 : 1)
                    .foregroundStyle(line.0 == "-" ? t.red : line.0 == "+" ? t.green : t.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 1)
                    .background(line.0 == "-" ? t.red.opacity(0.12) : line.0 == "+" ? t.green.opacity(0.12) : .clear)
            }
            if lines.count > 12 {
                Text("… \(lines.count - 12) more lines").foregroundStyle(t.overlay).padding(.horizontal, 8)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 6)
        .background(t.surface.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Just enough Markdown for plans: headings, bullets and inline styles
struct Markdown: View {
    let text: String
    let t: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    Text(inline(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(t.text).padding(.top, 4)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    Text(inline("•  " + line.dropFirst(2))).font(.system(size: 12)).foregroundStyle(t.text)
                } else if !line.isEmpty {
                    Text(inline(line)).font(.system(size: 12)).foregroundStyle(t.text)
                }
            }
        }
    }

    func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct Pill: ButtonStyle {
    let bg, fg: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(bg.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
    }
}
