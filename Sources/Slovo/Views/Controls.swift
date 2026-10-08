import SwiftUI
import AppKit
import TransCore

// Switches, choices, round buttons and tiles drawn by the app, as in FaceID.

/// Sinks when pressed, springs back with a little bounce.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    private struct PressBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
                .brightness(configuration.isPressed ? -0.06 : 0)
                .animation(configuration.isPressed ? .spring(response: 0.18, dampingFraction: 0.8)
                                                   : .spring(response: 0.35, dampingFraction: 0.45),
                           value: configuration.isPressed)
        }
    }
}

// MARK: - Switch

/// A switch as on iPhone: the brand color with a black knob when on, the knob stretches while pressed and slides with
/// a spring.
struct Switch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            Haptics.tap()
        } label: {
            EmptyView()
        }
        .buttonStyle(SwitchStyle(isOn: isOn))
        .accessibilityValue(isOn ? L("Вкл") : L("Выкл"))
    }

    private struct SwitchStyle: ButtonStyle {
        let isOn: Bool

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed
            Capsule()
                .fill(isOn ? Brand.color : Color.white.opacity(0.22))
                .frame(width: 36, height: 21)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Brand.ink : .white)
                        .frame(width: pressed ? 22 : 17, height: 17)
                        .padding(2)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }
                .contentShape(Capsule())
                .animation(.spring(response: 0.3, dampingFraction: 0.68), value: isOn)
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: pressed)
        }
    }
}

// MARK: - Segments

/// A choice drawn by the app: the white pill slides to the chosen option. `help` tells what an option with a short
/// title means, when pointed at and to VoiceOver.
struct Segments<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var help: ((Value) -> String)?
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.0) { value, title in
                Button {
                    guard selection != value else { return }
                    selection = value
                    Haptics.tap()
                } label: {
                    Text(title)
                        .font(.system(size: 12, weight: selection == value ? .semibold : .regular))
                        .foregroundStyle(selection == value ? Color.black : Color.white.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background {
                            if selection == value {
                                Capsule().fill(Color.white).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .help(help?(value) ?? "")
                .accessibilityLabel(help?(value) ?? title)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.control))
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: selection)
    }
}

// MARK: - Round buttons

/// An SF Symbol in a translucent circle.
struct RoundIcon: View {
    let symbol: String
    var size: CGFloat = 28
    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(hovering ? 0.18 : 0.12)))
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A small round button with an SF Symbol; `help` is its tooltip and its name for VoiceOver.
struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundIcon(symbol: symbol, size: size)
        }
        .buttonStyle(PressStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Tiles

/// A tile as in Control Center: a wide pill with an icon circle and a one-line name. A switch tile turns the circle
/// to the brand color (the icon black), bounces the icon, spreads a ring and taps the trackpad when it changes; a menu tile shows
/// the current value with a chevron and opens a menu.
private struct TileFace: View {
    let symbol: String
    let title: String
    let on: Bool
    var chevron = false
    var ripples = 0
    var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(on ? Brand.ink : .white)
                .bounce(on: on)
                .frame(width: 28, height: 28)
                .background(Circle().fill(on ? Brand.color : Color.white.opacity(0.16)))
                .background {
                    if !reduceMotion { RippleRing(color: on ? Brand.color : .white, trigger: ripples) }
                }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.trailing, 6)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(hovering ? 0.13 : 0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// The ring that spreads out from a tile's circle when the switch changes (macOS 14 and later).
private struct RippleRing: View {
    let color: Color
    let trigger: Int

    var body: some View {
        if #available(macOS 14.0, *) {
            Circle()
                .stroke(color, lineWidth: 2)
                .keyframeAnimator(initialValue: Ripple(), trigger: trigger) { view, ripple in
                    view.scaleEffect(ripple.scale).opacity(ripple.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0.8, duration: 0.01)
                        LinearKeyframe(0, duration: 0.45)
                    }
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(1, duration: 0.01)
                        CubicKeyframe(1.6, duration: 0.45)
                    }
                }
        }
    }

    private struct Ripple {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }
}

/// A switch tile; pointing at it tells what it does.
struct SwitchTile: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool
    let help: String
    @State private var hovering = false
    @State private var ripples = 0

    var body: some View {
        Button {
            isOn.toggle()
            Haptics.tap()
        } label: {
            TileFace(symbol: symbol, title: title, on: isOn, ripples: ripples, hovering: hovering)
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .help(help)
        // Also when the switch is flipped in Settings.
        .onChange(of: isOn) { _ in ripples += 1 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? L("Вкл") : L("Выкл"))
    }
}

/// A tile that shows a value and opens a menu with the other values.
struct MenuTile: View {
    let symbol: String
    let title: String
    let help: String
    let makeMenu: () -> NSMenu
    @State private var hovering = false
    @State private var anchor = ViewAnchor()

    var body: some View {
        Button {
            anchor.popUp(makeMenu())
        } label: {
            TileFace(symbol: symbol, title: title, on: false, chevron: true, hovering: hovering)
                .background(AnchorView(anchor: anchor))
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(title)
    }
}

/// A small capsule with the current value and a chevron that opens a menu (rows of settings).
struct MenuCapsule: View {
    let title: String
    let help: String
    let makeMenu: () -> NSMenu
    @State private var hovering = false
    @State private var anchor = ViewAnchor()

    var body: some View {
        Button {
            anchor.popUp(makeMenu())
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.18 : 0.12)))
            .contentShape(Capsule())
            .background(AnchorView(anchor: anchor))
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(title)
    }
}

// MARK: - Progress

/// A thin capsule filling with the brand color; without a value it breathes (see `Motion.breathe`: a piece sliding at
/// the display's rate kept the CPU busy), and with Reduce Motion it is half lit.
struct ProgressBar: View {
    var value: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.control)
                if let value {
                    Capsule()
                        .fill(Brand.color)
                        .frame(width: max(6, proxy.size.width * min(1, max(0, value))))
                } else {
                    BreathingBar(breathes: !reduceMotion)
                }
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

/// The capsule of a progress bar without a value, breathing in Core Animation.
private struct BreathingBar: NSViewRepresentable {
    let breathes: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Brand.nsColor.cgColor
        view.layer?.cornerRadius = 3
        view.layer?.opacity = 0.5
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Motion.breathe(view.layer, breathes, from: 0.75, to: 0.15)
    }
}

// MARK: - Menus

/// Weak reference to an AppKit view placed behind a SwiftUI control (to attach menus to it).
final class ViewAnchor {
    weak var view: NSView?

    /// Opens `menu` under the view. SwiftUI's Menu on macOS draws a pop-up button of its own, so the app's capsules
    /// and tiles open a native menu this way.
    func popUp(_ menu: NSMenu) {
        guard let view else { return }
        let below = view.isFlipped ? view.bounds.maxY + 6 : view.bounds.minY - 6
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: below), in: view)
    }
}

struct AnchorView: NSViewRepresentable {
    let anchor: ViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func run() {
        handler()
    }
}
