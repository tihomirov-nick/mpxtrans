import SwiftUI

/// Capsule buttons drawn by the app, as in FaceID: the main action is filled with the brand color, the others are
/// translucent white. They sink when pressed, spring back with a little bounce and grow a bit under the pointer.
struct AppButtonStyle: ButtonStyle {
    enum Kind {
        /// The main action: a filled capsule in the brand color.
        case primary
        /// Everything else: a translucent capsule.
        case secondary
        /// Deleting: a red-tinted capsule.
        case destructive
        /// A word in the brand color without a capsule, like the actions in iPhone Settings.
        case link
    }

    var kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        AppButtonBody(kind: kind, configuration: configuration)
    }
}

private struct AppButtonBody: View {
    let kind: AppButtonStyle.Kind
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: fontSize, weight: kind == .primary ? .semibold : .medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, isLink ? 0 : padding.h)
            .padding(.vertical, isLink ? 2 : padding.v)
            .frame(minWidth: controlSize == .large && !isLink ? 104 : nil)
            .background {
                if !isLink {
                    Capsule().fill(background(pressed: pressed))
                }
            }
            .contentShape(Capsule())
            .scaleEffect(pressed && !reduceMotion ? 0.92 : (hovering && !isLink && !reduceMotion ? 1.03 : 1))
            .brightness(pressed && kind == .primary ? -0.06 : 0)
            .opacity(isEnabled ? (isLink && (hovering || pressed) ? 0.7 : 1) : 0.4)
            // In quickly, back out with a little bounce, like iOS buttons.
            .animation(pressed ? .spring(response: 0.18, dampingFraction: 0.8) : .spring(response: 0.35, dampingFraction: 0.5),
                       value: pressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
    }

    private var isLink: Bool { kind == .link }

    private var fontSize: CGFloat {
        switch controlSize {
        case .mini, .small: 12
        case .large: 14.5
        default: 13
        }
    }

    private var padding: (h: CGFloat, v: CGFloat) {
        switch controlSize {
        case .mini, .small: (12, 5)
        case .large: (22, 10)
        default: (16, 7)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .secondary: .white
        case .destructive: .red
        case .link: Brand.color
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary:
            return Brand.color.opacity(pressed ? 0.75 : (hovering ? 0.92 : 1))
        case .secondary:
            return Color.white.opacity(pressed ? 0.24 : (hovering ? 0.2 : 0.14))
        case .destructive:
            return Color.red.opacity(pressed ? 0.26 : (hovering ? 0.2 : 0.14))
        case .link:
            return .clear
        }
    }
}

extension View {
    func appButton(_ kind: AppButtonStyle.Kind = .secondary) -> some View {
        buttonStyle(AppButtonStyle(kind: kind))
    }
}
