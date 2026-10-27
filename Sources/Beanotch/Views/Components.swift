import CoreText
import SwiftUI

enum Theme {
    // Set from Settings; the panel is rebuilt when they change.
    nonisolated(unsafe) static var accent = AccentChoice.mint.primary
    nonisolated(unsafe) static var accent2 = AccentChoice.mint.secondary

    static let good = Color(red: 0.33, green: 0.86, blue: 0.62)
    static let amber = Color(red: 0.98, green: 0.68, blue: 0.22)
    static let red = Color(red: 1.0, green: 0.4, blue: 0.4)

    // Set in the Retro theme: the colours below then come from its phosphor instead.
    nonisolated(unsafe) static var retro: Phosphor?

    static var ink: Color { retro?.color ?? baseInk }
    static var background: Color { retro?.background ?? baseBackground }
    static var surface: Color { retro.map { $0.color.opacity(0.05) } ?? baseSurface }
    static var stroke: Color { retro.map { $0.color.opacity(0.16) } ?? baseStroke }
    static var thumb: Color { retro.map { $0.color.opacity(0.2) } ?? baseThumb }
    static var dim: Color { ink.opacity(0.55) }
    static var faint: Color { ink.opacity(0.4) }

    // White on the dark panel, near-black on the light one.
    private static let baseInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : NSColor(white: 0.08, alpha: 1)
    })
    // Charcoal with lighter cards in the dark; a warm off-white with white cards in the light.
    private static let baseBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)
            : NSColor(srgbRed: 0.953, green: 0.953, blue: 0.945, alpha: 1)
    })
    private static let baseSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.045)
            : NSColor(white: 1, alpha: 1)
    })
    private static let baseStroke = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.07)
    })
    // The raised thumb of a segmented control: lifted grey in the dark, white in the light.
    private static let baseThumb = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.14) : .white
    })
    // SF Pro by default: it's drawn to sit with SF Symbols, which every icon here is.
    nonisolated(unsafe) static var font = AppFont.system

    static func level(_ value: Double) -> Color {
        value < 0.7 ? good : value < 0.9 ? amber : red
    }
}

struct Pill: View {
    var text: String
    var color: Color = Theme.dim
    var icon: String?
    var dot = false

    var body: some View {
        HStack(spacing: 4) {
            if dot { Circle().fill(color).frame(width: 5, height: 5) }
            if let icon { Image(systemName: icon).font(.system(size: 7, weight: .black)) }
            Text(text).lineLimit(1)
        }
        .font(.app(size: 8.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color.opacity(0.12)))
    }
}

// A flat face with a hairline edge that lights up a little under the pointer: depth from the press, not from
// sheen and shadow.
private struct ButtonFace<S: InsettableShape>: ViewModifier {
    let shape: S
    let color: Color
    // Bare until pointed at: for small icon buttons that sit in rows.
    var quiet = false
    @State private var hovered = false

    func body(content: Content) -> some View {
        let shown = !quiet || hovered
        content
            .background {
                shape.fill(shown ? color : .clear)
                    .overlay(shape.fill(Theme.ink.opacity(hovered ? 0.06 : 0)))
                    .overlay(shape.strokeBorder(Theme.ink.opacity(!shown ? 0 : hovered ? 0.14 : 0.07), lineWidth: 0.5))
            }
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

extension View {
    func buttonFace<S: InsettableShape>(_ shape: S, _ color: Color, quiet: Bool = false) -> some View {
        modifier(ButtonFace(shape: shape, color: color, quiet: quiet))
    }
}

// Sinks a little while held, like a physical key.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

struct PillButton: View {
    var text: String
    var icon: String?
    var color: Color = Theme.dim
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 7, weight: .black)) }
                Text(text).lineLimit(1)
            }
            .font(.app(size: 8.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .buttonFace(RoundedRectangle(cornerRadius: 6, style: .continuous), color.opacity(0.16))
        }
        .buttonStyle(PressStyle())
    }
}

struct IconButton: View {
    var icon: String
    var active = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? Theme.ink : Theme.dim)
                .frame(width: 24, height: 22)
                .buttonFace(RoundedRectangle(cornerRadius: 7, style: .continuous), Theme.ink.opacity(active ? 0.14 : 0.08), quiet: !active)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

struct OutlineButton: View {
    var text: String
    var color: Color = Theme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.app(size: 9.5, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .buttonFace(RoundedRectangle(cornerRadius: 7, style: .continuous), Theme.ink.opacity(0.08))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

struct PrimaryButton: View {
    var text: String
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(text).font(.app(size: 11, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .buttonFace(RoundedRectangle(cornerRadius: 9, style: .continuous), Theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

// One figure in a dashboard strip: a colored dot and label, the value, a caption under it.
struct StatCell: View {
    var label: String
    var color: Color
    var value: String
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label).font(.app(size: 9.5, weight: .medium)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Text(value).font(.app(size: 16, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(caption).font(.app(size: 8.5)).foregroundStyle(Theme.faint).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    // The rounded, hairline-edged card every dashboard block sits on.
    func card(radius: CGFloat = 12) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.app(size: 8.5, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.faint)
            }
            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
    }
}

enum NotchStyle: String, CaseIterable {
    case drop, seamless, floating

    var title: String { rawValue.capitalized }

    // Seamless's flared top corners take this much from each side; the panel grows by it and content steps in.
    static let ear: CGFloat = 18
}

// The panel's outline, opening out of the notch in one of three ways:
// - drop: notch-wide inside the menu bar, widening below it with soft shoulders;
// - seamless: full width from the screen's top edge, its top corners flaring out like the notch's own;
// - floating: the notch stays as it is and the panel is a separate card just under the menu bar.
struct NotchShape: Shape {
    var style: NotchStyle
    var neckWidth: CGFloat
    var neckHeight: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(neckWidth, radius) }
        set { neckWidth = newValue.first; radius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let nw = min(neckWidth, rect.width)
        let nh = min(neckHeight, rect.height)
        let shoulder = (rect.width - nw) / 2
        let body = rect.height - nh
        guard shoulder > 1, body > 1 else { return closed(rect) }
        switch style {
        case .drop: return drop(rect, nw: nw, nh: nh, shoulder: shoulder, body: body)
        case .seamless: return seamless(rect)
        case .floating: return floating(rect, nw: nw, nh: nh, body: body)
        }
    }

    private func closed(_ rect: CGRect) -> Path {
        UnevenRoundedRectangle(bottomLeadingRadius: min(radius, rect.height / 2),
                               bottomTrailingRadius: min(radius, rect.height / 2),
                               style: .continuous).path(in: rect)
    }

    private func drop(_ rect: CGRect, nw: CGFloat, nh: CGFloat, shoulder: CGFloat, body: CGFloat) -> Path {
        let fillet = min(14, shoulder / 2, body / 2)
        let top = min(20, shoulder - fillet, body / 2)
        let r = min(radius, body / 2)
        let left = rect.midX - nw / 2, right = rect.midX + nw / 2
        var p = Path()
        p.move(to: CGPoint(x: left - fillet, y: rect.minY))
        p.addLine(to: CGPoint(x: right + fillet, y: rect.minY))
        // Concave curves from the notch into the shoulders, so the neck doesn't meet the body at a corner.
        p.addCurve(to: CGPoint(x: right + fillet * 2, y: nh), control1: CGPoint(x: right + fillet * 1.1, y: nh * 0.55),
                   control2: CGPoint(x: right + fillet * 1.2, y: nh))
        p.addLine(to: CGPoint(x: rect.maxX - top, y: nh))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: nh + top), control: CGPoint(x: rect.maxX, y: nh))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: nh + top))
        p.addQuadCurve(to: CGPoint(x: rect.minX + top, y: nh), control: CGPoint(x: rect.minX, y: nh))
        p.addLine(to: CGPoint(x: left - fillet * 2, y: nh))
        p.addCurve(to: CGPoint(x: left - fillet, y: rect.minY), control1: CGPoint(x: left - fillet * 1.2, y: nh),
                   control2: CGPoint(x: left - fillet * 1.1, y: nh * 0.55))
        p.closeSubpath()
        return p
    }

    private func seamless(_ rect: CGRect) -> Path {
        let ear = min(NotchStyle.ear, rect.width / 4, rect.height / 2)
        let r = min(radius + 4, (rect.height - ear) / 2)
        let left = rect.minX + ear, right = rect.maxX - ear
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Concave flare from the screen's top edge into the side, the way the notch itself meets the menu bar.
        p.addCurve(to: CGPoint(x: left, y: rect.minY + ear * 1.4), control1: CGPoint(x: rect.minX + ear * 0.75, y: rect.minY),
                   control2: CGPoint(x: left, y: rect.minY + ear * 0.45))
        p.addLine(to: CGPoint(x: left, y: rect.maxY - r))
        p.addCurve(to: CGPoint(x: left + r, y: rect.maxY), control1: CGPoint(x: left, y: rect.maxY - r * 0.45),
                   control2: CGPoint(x: left + r * 0.45, y: rect.maxY))
        p.addLine(to: CGPoint(x: right - r, y: rect.maxY))
        p.addCurve(to: CGPoint(x: right, y: rect.maxY - r), control1: CGPoint(x: right - r * 0.45, y: rect.maxY),
                   control2: CGPoint(x: right, y: rect.maxY - r * 0.45))
        p.addLine(to: CGPoint(x: right, y: rect.minY + ear * 1.4))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control1: CGPoint(x: right, y: rect.minY + ear * 0.45),
                   control2: CGPoint(x: rect.maxX - ear * 0.75, y: rect.minY))
        p.closeSubpath()
        return p
    }

    private func floating(_ rect: CGRect, nw: CGFloat, nh: CGFloat, body: CGFloat) -> Path {
        let gap: CGFloat = 8
        var p = closed(CGRect(x: rect.midX - nw / 2, y: rect.minY, width: nw, height: nh))
        let card = CGRect(x: rect.minX, y: nh + gap, width: rect.width, height: max(0, body - gap))
        p.addRoundedRect(in: card, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return p
    }
}

// Core Animation bars: the render server animates them, so a playing song costs the app no CPU.
struct Equalizer: NSViewRepresentable {
    var playing: Bool
    var count = 4
    var color: Color = Theme.accent

    func makeNSView(context: Context) -> EqualizerView { EqualizerView() }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.configure(count: count, color: NSColor(color), playing: playing)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerView, context: Context) -> CGSize? {
        CGSize(width: CGFloat(count) * 4.5 - 2, height: 14)
    }
}

final class EqualizerView: NSView {
    private var bars: [CALayer] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    func configure(count: Int, color: NSColor, playing: Bool) {
        if bars.count != count {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<count).map { _ in
                let bar = CALayer()
                bar.cornerRadius = 1.25
                layer?.addSublayer(bar)
                return bar
            }
            needsLayout = true
        }
        for (i, bar) in bars.enumerated() {
            bar.backgroundColor = color.cgColor
            if playing, bar.animation(forKey: "eq") == nil {
                let a = CABasicAnimation(keyPath: "transform.scale.y")
                a.fromValue = 0.3
                a.toValue = 1
                a.duration = 0.32 + Double(i % 4) * 0.11
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timeOffset = Double(i) * 0.13
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(a, forKey: "eq")
            } else if !playing {
                bar.removeAnimation(forKey: "eq")
                bar.transform = CATransform3DMakeScale(1, 0.3, 1)
            }
        }
    }

    override func layout() {
        super.layout()
        for (i, bar) in bars.enumerated() {
            bar.frame = CGRect(x: CGFloat(i) * 4.5, y: 0, width: 2.5, height: bounds.height)
        }
    }
}

extension Font {
    static func registerAppFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        CTFontManagerRegisterFontURLs(urls.filter { $0.pathExtension == "ttf" } as CFArray, .process, true, nil)
    }

    // Figures, sizes and times, the way a dashboard sets them apart from labels.
    static func mono(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        if Theme.retro != nil { return retroFace(size) }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    // VT323 is a terminal font with a small body, so it's set a size up to read like the others.
    private static func retroFace(_ size: CGFloat) -> Font { .custom("VT323-Regular", size: size * 1.32) }

    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if Theme.retro != nil { return retroFace(size) }
        guard let prefix = Theme.font.prefix else { return .system(size: size, weight: weight) }
        let face = switch weight {
        case .bold, .heavy, .black: "Bold"
        case .semibold: "SemiBold"
        case .medium: "Medium"
        default: "Regular"
        }
        return .custom("\(prefix)-\(face)", size: size)
    }
}

// The Retro theme's CRT glass: a faint dark line every few points, and a soft darkening towards the edges. Drawn, so
// it costs nothing to ship, and it lets every click through.
struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.22)))
                y += 3
            }
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.28)]),
                                               center: CGPoint(x: size.width / 2, y: size.height / 2),
                                               startRadius: min(size.width, size.height) * 0.35,
                                               endRadius: max(size.width, size.height) * 0.75))
        }
        .allowsHitTesting(false)
    }
}

struct SearchField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.app(size: 11))
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.ink.opacity(0.06)))
    }
}

struct Placeholder<Action: View>: View {
    var icon: String
    var title: String
    var caption: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 22, weight: .light))
            Text(title).font(.app(size: 11.5, weight: .semibold))
            Text(caption).font(.app(size: 9.5)).multilineTextAlignment(.center).frame(maxWidth: 300)
            action.padding(.top, 4)
        }
        .foregroundStyle(Theme.faint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Placeholder where Action == EmptyView {
    init(icon: String, title: String, caption: String) {
        self.init(icon: icon, title: title, caption: caption) { EmptyView() }
    }
}

// Options on a quiet track; the chosen one sits on a raised neutral thumb that slides between them.
struct Segmented: View {
    var options: [String]
    @Binding var selection: Int
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let selected = selection == i
                Button { withAnimation(.snappy(duration: 0.22)) { selection = i } } label: {
                    Text(options[i])
                        .font(.app(size: 10, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.ink : Theme.dim)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.thumb)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.ink.opacity(0.055)))
    }
}

// A tab's icon drawn as a tinted template image: steadier across light and dark than a live symbol.
struct TabIcon: View {
    let name: String
    var size: CGFloat = 11
    var weight: NSFont.Weight = .medium

    var body: some View {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            Image(nsImage: image).renderingMode(.template)
        } else {
            Image(systemName: name).font(.system(size: size, weight: .medium))
        }
    }
}

// A small spinner with what's being waited for.
struct LoadingView: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.app(size: 10)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// The page at full height when it fits, scrolling when the panel is shorter than it (small sizes, roomy layouts).
struct FitOrScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical) { content }.scrollIndicators(.never)
        }
    }
}

func shortPath(_ url: URL) -> String {
    url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
}

// The system switch greys out whenever the panel isn't the key window, which is most of the time; this one
// keeps its color.
struct AccentSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? Theme.accent : Theme.ink.opacity(0.14))
                .frame(width: 30, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                }
                .animation(.snappy(duration: 0.18), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

// What sits beside the camera grows out of the notch: blurred and narrow at first, then sharp.
extension AnyTransition {
    static var emerge: AnyTransition {
        .modifier(active: Emerge(amount: 1), identity: Emerge(amount: 0)).combined(with: .opacity)
    }
}

private struct Emerge: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: 10 * amount)
            .scaleEffect(x: 1 - 0.7 * amount, y: 1, anchor: .center)
    }
}

// Click, then press the new combination (with at least one of ⌘ ⌥ ⌃ ⇧); Esc cancels.
struct ShortcutRecorder: View {
    @EnvironmentObject var settings: Settings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            Text(recording ? "Press keys…" : settings.hotkeyLabel)
                .font(.app(size: 10, weight: .semibold))
                .foregroundStyle(recording ? Theme.accent : Theme.ink)
                .padding(.horizontal, 10)
                .frame(minWidth: 70)
                .frame(height: 22)
                .buttonFace(RoundedRectangle(cornerRadius: 7, style: .continuous), Theme.ink.opacity(recording ? 0.14 : 0.08))
        }
        .buttonStyle(PressStyle())
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        // Key presses only reach the panel while it's the key window.
        NSApp.windows.first { $0 is NotchPanel && $0.isVisible && !$0.ignoresMouseEvents }?.makeKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty else { return nil }
            var carbon = 0
            if flags.contains(.command) { carbon |= 256 }
            if flags.contains(.shift) { carbon |= 512 }
            if flags.contains(.option) { carbon |= 2048 }
            if flags.contains(.control) { carbon |= 4096 }
            let symbols = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
                + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            settings.setHotkey(code: Int(event.keyCode), modifiers: carbon, label: symbols + " " + Self.keyName(event))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func keyName(_ event: NSEvent) -> String {
        let named: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
            109: "F10", 103: "F11", 111: "F12",
        ]
        return named[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
