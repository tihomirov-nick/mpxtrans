import AppKit
import Combine
import TransCore

/// The icon in the menu bar while a transcription runs: the app icon in lines, its squircle with the mark inside,
/// sound waves on the left that run into the middle and calm down there, and the word's line on the right that grows
/// as recognition goes on. At the end it shows the line whole (or a cross) for a moment
/// and goes away; a click brings the window forward. The animation is light (4 frames a second) and stops while the
/// displays sleep or Reduce Motion is on: then only the progress changes the icon. Drawn in code as a template image
/// like the menu bar icons of the author's other apps: 16 × 16 pt, the glyph in the middle 14 × 14 pt, 1.5 pt lines
/// with round ends.
@MainActor
final class MenuBarIcon: NSObject {
    /// What the icon shows: where the waves are in their run and the word's line, being written or finished.
    struct Glyph: Equatable {
        enum Line: Equatable {
            /// Written so far, 0...1.
            case progress(Double)
            case done
            case failed
        }

        /// The phase of the waves, in radians.
        var phase: CGFloat
        var line: Line
    }

    static let defaultsKey = "menuBarIcon"

    private let transcriber: Transcriber
    private var item: NSStatusItem?
    private var timer: Timer?
    private var ending: DispatchWorkItem?
    private var subscriptions: Set<AnyCancellable> = []
    private var displaysAsleep = false
    private var shown: Glyph?
    private let clock = Date()

    init(transcriber: Transcriber) {
        self.transcriber = transcriber
        super.init()
        transcriber.$phase.removeDuplicates().sink { [weak self] phase in
            // @Published sends before the value changes: read it on the next turn.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.phaseChanged(to: phase) } }
        }.store(in: &subscriptions)
        transcriber.$step.combineLatest(transcriber.$stepProgress).sink { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }.store(in: &subscriptions)
        transcriber.$menuBarIcon.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.phaseChanged(to: transcriber.phase) } }
        }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(motionMayChange), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(motionMayChange), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(motionMayChange),
                           name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    // MARK: - Showing

    private func phaseChanged(to phase: Transcriber.Phase) {
        guard transcriber.menuBarIcon else { return hide() }
        switch phase {
        case .working:
            ending?.cancel()
            ending = nil
            show()
        case .done:
            if item != nil { finish(.done) }
        case .idle:
            // Cancelled by the user: away at once; failed: the cross first.
            if item != nil { transcriber.errorMessage != nil ? finish(.failed) : hide() }
        }
    }

    private func show() {
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(bringWindowForward)
            item.button?.imagePosition = .imageOnly
            self.item = item
        }
        updateTimer()
        refresh()
    }

    /// The whole line or the cross for 1.5 s, then away.
    private func finish(_ line: Glyph.Line) {
        timer?.invalidate()
        timer = nil
        draw(Glyph(phase: Self.restingPhase, line: line))
        item?.button?.toolTip = line == .done ? L("Расшифровка готова") : L("Не получилось")
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        ending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func hide() {
        ending?.cancel()
        ending = nil
        timer?.invalidate()
        timer = nil
        shown = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @objc private func bringWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Animation

    private var moves: Bool {
        !displaysAsleep && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @objc private func motionMayChange(_ notification: Notification) {
        if notification.name == NSWorkspace.screensDidSleepNotification { displaysAsleep = true }
        if notification.name == NSWorkspace.screensDidWakeNotification { displaysAsleep = false }
        updateTimer()
        refresh()
    }

    private func updateTimer() {
        let wanted = item != nil && ending == nil && transcriber.phase == .working && moves
        guard wanted != (timer != nil) else { return }
        if wanted {
            // 4 frames a second: redrawing an item of the menu bar costs more than drawing the glyph, and 10 frames a
            // second took about 5 % of the CPU.
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    /// The current frame and the tooltip.
    private func refresh() {
        guard let item, ending == nil, transcriber.phase == .working else { return }
        // Rounded to the 64th, a fraction of a pixel of the line: finer steps would only cost redraws.
        let written = transcriber.step == .recognizing ? ((transcriber.stepProgress ?? 0) * 64).rounded() / 64 : 0
        let phase = moves ? Self.phase(at: Date().timeIntervalSince(clock)) : Self.restingPhase
        draw(Glyph(phase: phase, line: .progress(written)))
        let tooltip = tooltipText()
        if item.button?.toolTip != tooltip {
            item.button?.toolTip = tooltip
            item.button?.setAccessibilityLabel(tooltip)
        }
    }

    private func draw(_ glyph: Glyph) {
        guard glyph != shown, let button = item?.button else { return }
        shown = glyph
        // One image that draws whatever is current: a new image every frame made the menu bar lay itself out again.
        live.glyph = glyph
        if button.image !== live.image {
            button.image = live.image
        } else {
            button.needsDisplay = true
        }
    }

    private func tooltipText() -> String {
        guard transcriber.step == .recognizing else {
            if let progress = transcriber.stepProgress {
                return L("%@ — %@ %%", transcriber.step.title, "\(Int(progress * 100))")
            }
            return transcriber.step.title
        }
        let percent = "\(Int((transcriber.stepProgress ?? 0) * 100))"
        if let left = transcriber.remainingTime(at: Date()) {
            return L("Расшифровка — %@ %%, осталось примерно %@", percent, formatDuration(max(1, left)))
        }
        return L("Расшифровка — %@ %%", percent)
    }

    // MARK: - Drawing

    /// Where the mark goes inside the squircle, in points of the 16 pt canvas (y down): the waves from `waveLeft` to
    /// `middle`, the line on to `lineEnd`, both along `axis`. The axis sits on a quarter point, so that the 1.5 pt line
    /// covers whole pixels at 2x. Inside the squircle a single wave fits with room between its strokes, and a faint one
    /// behind it.
    private enum Layout {
        static let waveLeft: CGFloat = 3.75
        static let middle: CGFloat = 8.25
        static let lineEnd: CGFloat = 12.25
        static let axis: CGFloat = 8.25
        /// How far the solid wave swings at the left edge; the faint one swings `faint` times as far.
        static let amplitude: CGFloat = 3.25
        static let faint: CGFloat = 0.8
        /// How many waves fit between the left edge and the middle.
        static let cycles: CGFloat = 1
        /// The side of the cross that takes the line's place when the transcription fails.
        static let cross: CGFloat = 2.75
    }

    /// At rest the waves lie as the app icon's do: the solid one leaves the axis upwards.
    nonisolated static let restingPhase = CGFloat.pi

    /// The waves run to the right, into the line, a wavelength in 2.4 s.
    nonisolated static func phase(at time: TimeInterval) -> CGFloat {
        restingPhase - CGFloat((time / 2.4).truncatingRemainder(dividingBy: 1)) * 2 * .pi
    }

    /// The image on the button: drawn anew whenever the button draws, from `glyph`.
    private final class LiveImage {
        var glyph = Glyph(phase: MenuBarIcon.restingPhase, line: .progress(0))
        lazy var image: NSImage = {
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { [unowned self] _ in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                MenuBarIcon.draw(self.glyph, in: ctx)
                return true
            }
            image.isTemplate = true
            image.cacheMode = .never
            return image
        }()
    }

    private let live = LiveImage()

    /// Draws a frame on the 16 × 16 pt canvas (y down), the glyph in the middle 14 × 14 pt: 1.5 pt lines with round
    /// ends, the far wave and what is not written yet faint.
    nonisolated static func draw(_ glyph: Glyph, in ctx: CGContext) {
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        func stroke(_ points: [CGPoint], alpha: CGFloat = 1) {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
            ctx.addLines(between: points)
            ctx.strokePath()
        }
        // The body of the app icon: its squircle along the edge of the 14 pt square.
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.addPath(squircle(CGRect(x: 1.75, y: 1.75, width: 12.5, height: 12.5)))
        ctx.strokePath()
        // The waves: the far one behind, swinging less and out of step like the second wave of the app icon.
        stroke(wave(amplitude: Layout.amplitude * Layout.faint, phase: glyph.phase + 3.6), alpha: 0.45)
        stroke(wave(amplitude: Layout.amplitude, phase: glyph.phase))
        let y = Layout.axis
        if glyph.line == .failed {
            // A cross in the place of the line, at its far end, clear of the waves.
            let right = Layout.lineEnd, left = right - Layout.cross, top = y - Layout.cross / 2, bottom = y + Layout.cross / 2
            stroke([CGPoint(x: left, y: top), CGPoint(x: right, y: bottom)])
            stroke([CGPoint(x: right, y: top), CGPoint(x: left, y: bottom)])
            return
        }
        let written: CGFloat
        switch glyph.line {
        case .progress(let value): written = CGFloat(min(1, max(0, value)))
        default: written = 1
        }
        stroke([CGPoint(x: Layout.middle, y: y), CGPoint(x: Layout.lineEnd, y: y)], alpha: 0.3)
        if written > 0 {
            stroke([CGPoint(x: Layout.middle, y: y), CGPoint(x: Layout.middle + (Layout.lineEnd - Layout.middle) * written, y: y)])
        }
    }

    /// A wave like those of the app icon: its swing holds on the left and fades out towards the middle, where the wave
    /// lies down on the axis and goes on as the line.
    private nonisolated static func wave(amplitude: CGFloat, phase: CGFloat) -> [CGPoint] {
        (0...40).map { i in
            let t = CGFloat(i) / 40
            return CGPoint(x: Layout.waveLeft + (Layout.middle - Layout.waveLeft) * t,
                           y: Layout.axis + amplitude * pow(cos(.pi / 2 * t), 1.6) * sin(2 * .pi * Layout.cycles * t + phase))
        }
    }

    /// Apple-style continuous corners (superellipse), the squircle of the app icon.
    private nonisolated static func squircle(_ rect: CGRect, exponent: CGFloat = 5) -> CGPath {
        let path = CGMutablePath()
        let a = rect.width / 2, b = rect.height / 2
        for i in 0...360 {
            let t = CGFloat(i) / 360 * 2 * .pi
            let c = cos(t), s = sin(t)
            let point = CGPoint(x: rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / exponent),
                                y: rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / exponent))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
