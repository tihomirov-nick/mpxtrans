import SwiftUI
import AppKit

// The look follows Apple's Liquid Glass (iOS 27 / macOS 26 design): controls float above the content on glass,
// content sits on calm surfaces, shapes are capsules and continuous rounded rectangles. On macOS 13–15 the same
// layout falls back to system materials.

// MARK: - Motion

/// Springs without overshoot; with Reduce Motion they become short cross-fades.
enum Motion {
    static let standard = Animation.spring(response: 0.42, dampingFraction: 0.9)
    static let quick = Animation.spring(response: 0.25, dampingFraction: 1)

    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : base
    }
}

// MARK: - Glass

extension View {
    /// Liquid Glass behind the view on macOS 26 and later, a material on earlier systems.
    @ViewBuilder
    func glassSurface<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    /// Capsule glass buttons as on iOS (macOS draws its own glass buttons as rounded rectangles).
    func glassButtonStyle(prominent: Bool = false) -> some View {
        buttonStyle(CapsuleGlassButtonStyle(prominent: prominent))
    }

    /// Round icon-only glass button.
    @ViewBuilder
    func glassCircleButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass).buttonBorderShape(.circle)
        } else if #available(macOS 14.0, *) {
            buttonStyle(.bordered).buttonBorderShape(.circle)
        } else {
            buttonStyle(.bordered)
        }
    }
}

/// Capsule button: Liquid Glass, or the accent color for the main action. Before macOS 26 a material.
struct CapsuleGlassButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let padding: (h: CGFloat, v: CGFloat) = switch controlSize {
        case .mini, .small: (10, 4)
        case .large: (16, 8)
        default: (13, 6)
        }
        return configuration.label
            .font(.system(size: controlSize == .small || controlSize == .mini ? 12 : 13, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .padding(.horizontal, padding.h)
            .padding(.vertical, padding.v)
            .contentShape(Capsule())
            .modifier(CapsuleBackground(prominent: prominent, pressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

private struct CapsuleBackground: ViewModifier {
    let prominent: Bool
    let pressed: Bool

    func body(content: Content) -> some View {
        if prominent {
            // Solid accent with a glassy highlight: tinted glass turns gray in an inactive window, and the result
            // usually arrives while Finder (where the file was dragged from) is the active app.
            let accent = Color(nsColor: .controlAccentColor)
            content.background(
                Capsule()
                    .fill(accent.opacity(pressed ? 0.82 : 1))
                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0)],
                                                           startPoint: .top, endPoint: .center)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5))
                    .shadow(color: accent.opacity(0.35), radius: 8, y: 3)
            )
        } else if #available(macOS 26.0, *) {
            content.glassEffect(Glass.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}

/// Glass shapes inside blend and morph together on macOS 26 (GlassEffectContainer).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Surfaces

/// Calm surface for reading and editing text: content is not glass, glass is for the controls above it.
struct PaperSurface: View {
    var cornerRadius: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

/// Soft colorful backdrop under the glass, like a wallpaper; the glass picks up its colors.
struct Backdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = colorScheme == .dark ? Self.dark : Self.light
        Group {
            if #available(macOS 15.0, *) {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.55, 0], [1, 0],
                    [0, 0.45], [0.45, 0.55], [1, 0.4],
                    [0, 1], [0.6, 1], [1, 1],
                ], colors: colors)
            } else {
                LinearGradient(colors: [colors[0], colors[4], colors[8]], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
    }

    private static let light: [Color] = [
        Color(hex: 0xD9E6FF), Color(hex: 0xE9DEFF), Color(hex: 0xFFE2EC),
        Color(hex: 0xD3EEFF), Color(hex: 0xF1EBFF), Color(hex: 0xFFEADB),
        Color(hex: 0xD5F7EC), Color(hex: 0xDCE9FF), Color(hex: 0xF2E3FF),
    ]
    private static let dark: [Color] = [
        Color(hex: 0x111B3D), Color(hex: 0x24164A), Color(hex: 0x36112E),
        Color(hex: 0x0D2840), Color(hex: 0x181735), Color(hex: 0x33201C),
        Color(hex: 0x082E2A), Color(hex: 0x111F48), Color(hex: 0x2A1342),
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

// MARK: - Small parts

/// Rounded numerals for percentages and timers.
extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// SF Symbol animation where the system supports it (macOS 14+).
struct PulsingSymbol: View {
    let name: String
    var active: Bool

    var body: some View {
        if #available(macOS 14.0, *) {
            Image(systemName: name)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: active)
        } else {
            Image(systemName: name)
        }
    }
}
