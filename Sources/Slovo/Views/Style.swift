import SwiftUI
import AppKit

// The look of FaceID (an app by the same author), moved from the notch island into an ordinary window: black
// surfaces with continuous corners, white text, cards in white 7%, dividers in white 8%, and buttons, switches and
// tiles drawn by the app rather than by macOS, so they look the same on every macOS version.

/// Slovo's color: white with a cool tint, as in Subline and the black and white icons of the author's apps. The main
/// button, switches that are on, progress, the drop zone; what lies on it, text and symbols, is `ink`.
enum Brand {
    static let color = Color(red: 0.96, green: 0.96, blue: 0.98)
    static let nsColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.98, alpha: 1)
    /// Text and symbols on the brand color.
    static let ink = Color.black
}

/// Shades of white on the black window.
enum Palette {
    /// A card or a tile on the black window.
    static let card = Color.white.opacity(0.07)
    /// A line between the rows of a card.
    static let divider = Color.white.opacity(0.08)
    /// Round buttons, the track of a choice, fields.
    static let control = Color.white.opacity(0.12)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)
}

// MARK: - Motion

enum Motion {
    /// FaceID's island spring: quick, with a little overshoot.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.74)
    static let quick = Animation.spring(response: 0.25, dampingFraction: 1)

    /// With Reduce Motion, movement becomes a short cross-fade.
    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : base
    }

    /// Opacity that falls and rises once in 1.6 s, played by Core Animation at 10 frames a second; `on` false stops it.
    static func breathe(_ layer: CALayer?, _ on: Bool, from: Float, to: Float) {
        guard let layer else { return }
        guard on else {
            layer.removeAnimation(forKey: "breath")
            return
        }
        guard layer.animation(forKey: "breath") == nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = 0.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 12, preferred: 10)
        layer.add(animation, forKey: "breath")
    }
}

/// New content appears the way FaceID's island shows it: out of a blur, growing from the top.
struct BlurAppear: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 10)
            .scaleEffect(0.85 + 0.15 * progress, anchor: .top)
    }
}

extension AnyTransition {
    static func blurAppear(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .modifier(active: BlurAppear(progress: 0), identity: BlurAppear(progress: 1))
    }
}

/// A tap on the trackpad when a switch flips (felt when a finger rests on the trackpad).
enum Haptics {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

// MARK: - Surfaces

/// The space under every block of the window, and around it.
enum Layout {
    static let padding: CGFloat = 12
    static let spacing: CGFloat = 8
    static let cardRadius: CGFloat = 16
}

extension View {
    /// A card on the black window: white 7% with continuous corners.
    func card(radius: CGFloat = Layout.cardRadius) -> some View {
        background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// The black window, title bar included: the windows hide the system title bar (`.hiddenTitleBar`), and
    /// `title` is drawn in its place next to the window buttons, like a page title in FaceID's island.
    func blackWindow(title: String? = nil) -> some View {
        foregroundStyle(.white)
            .tint(Brand.color)
            .overlay(alignment: .top) {
                if let title {
                    // Right above the content, in the band of the title bar.
                    WindowTitle(text: title).offset(y: -WindowTitle.height)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .background(BlackWindow())
            .preferredColorScheme(.dark)
    }

    /// Bounces an SF Symbol when `value` changes (macOS 14 and later).
    @ViewBuilder
    func bounce<V: Equatable>(on value: V) -> some View {
        if #available(macOS 14.0, *) {
            symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }
}

/// A 1-pt line between the rows of a card.
struct RowDivider: View {
    var leading: CGFloat = 12

    var body: some View {
        Rectangle().fill(Palette.divider).frame(height: 1).padding(.leading, leading)
    }
}

/// A window's title in the band of the title bar (28 pt, the window buttons in its middle), dimmed while the
/// window is in the background.
private struct WindowTitle: View {
    static let height: CGFloat = 28
    let text: String
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(activeState == .inactive ? 0.4 : 0.85))
            .lineLimit(1)
            .padding(.horizontal, 80)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .allowsHitTesting(false)
    }
}

/// Dark appearance and a black background for the hosting window (no flash of gray while it opens or resizes).
struct BlackWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowHook()
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowHook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
        }
    }
}

// MARK: - Small parts

/// An SF Symbol that breathes while `active`: its opacity falls and rises once in 1.6 s. Core Animation does it at
/// 10 frames a second in the render server, so the app does nothing per frame during a long transcription (a
/// repeating symbol effect kept the CPU busy). Still with Reduce Motion.
struct PulsingSymbol: NSViewRepresentable {
    let name: String
    var size: CGFloat
    var weight: NSFont.Weight = .regular
    var color: Color
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.wantsLayer = true
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
        view.contentTintColor = NSColor(color)
        Motion.breathe(view.layer, active && !reduceMotion, from: 1, to: 0.4)
    }
}

/// Keeps a label as wide as its widest variant ("Copy" and "Copied"), so the buttons next to it do not move.
struct StableLabel: View {
    let text: String
    let variants: [String]

    var body: some View {
        ZStack {
            ForEach(variants, id: \.self) { Text($0).hidden() }
            Text(text)
        }
    }
}
