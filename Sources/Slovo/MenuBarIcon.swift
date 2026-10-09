import AppKit
import Combine
import TransCore

/// The icon in the menu bar while a transcription runs: the mark of the app icon in lines, sound waves on the left that
/// run into the middle and calm down there, and the word's line on the right that grows as recognition goes on. At the
/// end it shows the line whole (or a cross) for a moment and goes away; a click brings the window forward. The animation
/// is light (4 frames a second) and stops while the displays sleep or Reduce Motion is on: then only the progress changes
/// the icon. Drawn in code as a template image like the menu bar icons of the author's other apps, the mark alone without
/// the squircle: 15 × 16 pt, the mark 14 pt across, 1.18 pt lines with round ends.
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

    /// The image: 15 pt wide, the width of the menu bar icons of all four apps of the family, so the gaps between them
    /// are the same. The status item is `variableLength`: as wide as the image plus the menu bar's own margins.
    nonisolated static let canvas = NSSize(width: 15, height: 16)

    /// Where the mark lies, in points of the canvas (y down). Like the app icon's mark it is split in the middle of the
    /// image: the waves on the left half, from `waveLeft`, run into one point at `middle`, and the line goes on to
    /// `lineEnd`, all along the axis (see `axis`). With its round ends the mark is 14 pt across, and the swing is as
    /// tall for its length as in the icon.
    private enum Layout {
        /// As thick as the lines of FaceID's icon in the menu bar.
        static let lineWidth: CGFloat = 1.18
        static let waveLeft = (MenuBarIcon.canvas.width - 14 + lineWidth) / 2
        static let middle = MenuBarIcon.canvas.width / 2
        static let lineEnd = MenuBarIcon.canvas.width - waveLeft
        /// How far the solid wave swings at the left end; the faint one swings `faint` times as far.
        static let amplitude: CGFloat = 3.5
        static let faint: CGFloat = 0.75
        /// The faint wave is drawn from 2x on: at 1x it has no pixels of its own and only blurs the solid one.
        static let faintFrom: CGFloat = 2
        /// A wave and a quarter fit between the left end and the middle.
        static let cycles: CGFloat = 1.25
        /// The side of the cross that takes the line's place when the transcription fails.
        static let cross: CGFloat = 3.5

        /// The axis: the middle of the height, moved to where the line covers whole pixels at `scale` as far as it
        /// can, onto a boundary between pixel rows when the line is an even number of pixels thick (2 at 2x), into the
        /// middle of a row when it is odd (1 at 1x).
        static func axis(scale: CGFloat) -> CGFloat {
            let middle = MenuBarIcon.canvas.height / 2
            guard scale > 0 else { return middle }
            let pixels = max(1, (lineWidth * scale).rounded())
            let offset: CGFloat = pixels.truncatingRemainder(dividingBy: 2) == 1 ? 0.5 : 0
            return ((middle * scale - offset).rounded(.down) + offset) / scale
        }
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
            let image = NSImage(size: MenuBarIcon.canvas, flipped: true) { [unowned self] _ in
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

    /// Draws a frame on the canvas (y down): lines with round ends, the far wave and what is not written yet faint.
    nonisolated static func draw(_ glyph: Glyph, in ctx: CGContext) {
        // The image is drawn once for each pixel density, so the line lands on whole pixels at 1x and at 2x.
        let scale = abs(ctx.userSpaceToDeviceSpaceTransform.a)
        let y = Layout.axis(scale: scale)
        ctx.setLineWidth(Layout.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        func stroke(_ points: [CGPoint], alpha: CGFloat = 1) {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
            ctx.addLines(between: points)
            ctx.strokePath()
        }
        // The waves: the far one behind, swinging less and out of step like the second wave of the app icon.
        if scale >= Layout.faintFrom {
            stroke(wave(amplitude: Layout.amplitude * Layout.faint, phase: glyph.phase + 3.6, axis: y), alpha: 0.45)
        }
        stroke(wave(amplitude: Layout.amplitude, phase: glyph.phase, axis: y))
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
    private nonisolated static func wave(amplitude: CGFloat, phase: CGFloat, axis: CGFloat) -> [CGPoint] {
        (0...40).map { i in
            let t = CGFloat(i) / 40
            return CGPoint(x: Layout.waveLeft + (Layout.middle - Layout.waveLeft) * t,
                           y: axis + amplitude * pow(cos(.pi / 2 * t), 1.6) * sin(2 * .pi * Layout.cycles * t + phase))
        }
    }
}
