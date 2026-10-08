import AppKit
import Combine
import TransCore

/// The icon in the menu bar while a transcription runs: the app icon in lines (style A: its squircle with the mark
/// inside; B: the mark alone), a wave of upright strokes that moves gently and lines of text that get written as
/// recognition goes on. At the end it shows the lines whole (or a cross) for a moment and goes away; a click brings
/// the window forward. The animation is light (4 frames a second) and stops while the displays sleep or Reduce Motion
/// is on: then only the progress changes the icon. Drawn in code as a template image like the menu bar icons of the
/// author's other apps: 16 × 16 pt, the glyph in the middle 14 × 14 pt, 1.5 pt lines with round ends.
@MainActor
final class MenuBarIcon: NSObject {
    /// What the icon shows: the heights of the wave's strokes and the text, being written or finished.
    struct Glyph: Equatable {
        enum Text: Equatable {
            /// Written so far, 0...1.
            case progress(Double)
            case done
            case failed
        }

        var wave: [CGFloat]
        var text: Text
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

    /// The finished lines or the cross for 1.5 s, then away.
    private func finish(_ text: Glyph.Text) {
        timer?.invalidate()
        timer = nil
        draw(Glyph(wave: Self.restingWave, text: text))
        item?.button?.toolTip = text == .done ? L("Расшифровка готова") : L("Не получилось")
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
        let written = transcriber.step == .recognizing ? transcriber.stepProgress ?? 0 : 0
        let wave = moves ? Self.wave(at: Date().timeIntervalSince(clock)) : Self.restingWave
        draw(Glyph(wave: wave, text: .progress(written)))
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

    /// A: the whole app icon in lines, the squircle and the mark inside it (the default); B: the mark alone.
    enum Style {
        case wholeIcon, markOnly
    }

    nonisolated static let style = Style.wholeIcon

    /// Where the strokes go, in points of the 16 pt canvas (y down). Centres sit on quarter points, so that 1.5 pt
    /// lines cover whole pixels at 2x.
    private struct Layout {
        var outline: Bool
        var waveX: [CGFloat]
        /// The height of a stroke at rest of 14 in the mark alone.
        var waveScale: CGFloat
        var waveMiddle: CGFloat
        var lineX: CGFloat
        var lineY: [CGFloat]
        var lineLength: [CGFloat]
        var caret: Bool

        /// Inside the 1.5 pt squircle only two strokes and three short lines fit with room between them.
        static let wholeIcon = Layout(outline: true, waveX: [4.75, 7.25], waveScale: 9 / 14, waveMiddle: 8.25, lineX: 9.25,
                                      lineY: [5.25, 8.25, 11.25], lineLength: [3.25, 2.5, 1.75], caret: false)
        /// The app icon's mark on the whole 14 pt square: three strokes, three lines and the caret.
        static let markOnly = Layout(outline: false, waveX: [1.75, 4.25, 6.75], waveScale: 1, waveMiddle: 8, lineX: 9,
                                     lineY: [4.25, 7.75, 11.25], lineLength: [6, 4.5, 2], caret: true)
    }

    nonisolated static let restingWave: [CGFloat] = [8.5, 14, 7]

    /// The strokes rise and fall out of step, around their resting heights, once in 2.4 s.
    nonisolated static func wave(at time: TimeInterval) -> [CGFloat] {
        let phase = time / 2.4 * 2 * .pi
        return restingWave.enumerated().map { index, height in
            let swing: CGFloat = index == 1 ? 2.5 : 2
            // Quantized to a quarter point, so frames that look the same are not drawn again.
            return ((height - swing + swing * CGFloat(sin(phase + Double(index) * 2.1))) * 4).rounded() / 4
        }
    }

    /// The image on the button: drawn anew whenever the button draws, from `glyph`.
    private final class LiveImage {
        var glyph = Glyph(wave: MenuBarIcon.restingWave, text: .progress(0))
        lazy var image: NSImage = {
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { [unowned self] _ in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                MenuBarIcon.draw(self.glyph, style: MenuBarIcon.style, in: ctx)
                return true
            }
            image.isTemplate = true
            image.cacheMode = .never
            return image
        }()
    }

    private let live = LiveImage()

    /// A template image of one frame.
    nonisolated static func image(_ glyph: Glyph, style: Style = style) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(glyph, style: style, in: ctx)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws a frame on the 16 × 16 pt canvas (y down), the glyph in the middle 14 × 14 pt: 1.5 pt lines with round
    /// ends, what is not written yet as a faint track.
    nonisolated static func draw(_ glyph: Glyph, style: Style, in ctx: CGContext) {
        let layout = style == .wholeIcon ? Layout.wholeIcon : Layout.markOnly
        let width: CGFloat = 1.5
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        func stroke(_ from: CGPoint, _ to: CGPoint, alpha: CGFloat = 1) {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()
        }
        if layout.outline {
            // The body of the app icon: its squircle along the edge of the 14 pt square.
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.addPath(squircle(CGRect(x: 1.75, y: 1.75, width: 12.5, height: 12.5)))
            ctx.strokePath()
        }
        for (index, x) in layout.waveX.enumerated() {
            let height = min(14, glyph.wave[index]) * layout.waveScale
            let half = max(0, height - width) / 2
            stroke(CGPoint(x: x, y: layout.waveMiddle - half), CGPoint(x: x, y: layout.waveMiddle + half))
        }
        let x = layout.lineX, lines = zip(layout.lineY, layout.lineLength).map { (y: $0, length: $1) }
        if glyph.text == .failed {
            // A cross in the place of the text.
            let left = x + 0.5, right = x + layout.lineLength[0] - 0.5, top = lines[0].y, bottom = lines[2].y
            stroke(CGPoint(x: left, y: top), CGPoint(x: right, y: bottom))
            stroke(CGPoint(x: right, y: top), CGPoint(x: left, y: bottom))
            return
        }
        var written: CGFloat
        switch glyph.text {
        case .progress(let value): written = CGFloat(min(1, max(0, value)))
        default: written = 1
        }
        var left = written * layout.lineLength.reduce(0, +)
        var caret: CGPoint?
        for (index, line) in lines.enumerated() {
            stroke(CGPoint(x: x + width / 2, y: line.y), CGPoint(x: x + line.length - width / 2, y: line.y), alpha: 0.3)
            let part = min(left, line.length)
            left -= part
            if part > 0 {
                stroke(CGPoint(x: x + width / 2, y: line.y), CGPoint(x: x + max(width, part) - width / 2, y: line.y))
            }
            // The caret stands where the writing is, after the last line at the end.
            if caret == nil, part < line.length || index == lines.count - 1 {
                caret = CGPoint(x: x + part + 1 + width / 2, y: line.y)
            }
        }
        if layout.caret, let caret {
            stroke(CGPoint(x: caret.x, y: caret.y - 1), CGPoint(x: caret.x, y: caret.y + 1))
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

    // MARK: - Checks (DebugHooks)

    /// Where the icon is on screen, while it is shown.
    var screenFrame: NSRect? { item?.button?.window?.frame }
    var tooltip: String? { item?.button?.toolTip }

    /// The frames as PNG, black on clear, for both styles: a second of the wave at 10 frames a second with the text half
    /// written, the text at 0, 50 and 100 %, done and failed. Each at 1x, 2x and enlarged 8 times (2x pixels shown 4 times).
    static func saveFrames(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var frames: [(String, Glyph)] = (0..<12).map { i in
            (String(format: "wave-%02d", i), Glyph(wave: wave(at: Double(i) / 10), text: .progress(0.5)))
        }
        frames += [("text-000", Glyph(wave: restingWave, text: .progress(0))),
                   ("text-050", Glyph(wave: restingWave, text: .progress(0.5))),
                   ("text-100", Glyph(wave: restingWave, text: .progress(1))),
                   ("done", Glyph(wave: restingWave, text: .done)),
                   ("failed", Glyph(wave: restingWave, text: .failed))]
        for (prefix, style) in [("A", Style.wholeIcon), ("B", Style.markOnly)] {
            for (name, glyph) in frames {
                for (suffix, pixels) in [("@1x", 16), ("@2x", 32)] {
                    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                     bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                    rep.size = NSSize(width: 16, height: 16)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    image(glyph, style: style).draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
                    NSGraphicsContext.restoreGraphicsState()
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: folder.appendingPathComponent("\(prefix)-\(name)\(suffix).png"))
                }
            }
        }
    }
}
