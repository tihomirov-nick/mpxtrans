import AppKit
import Combine
import TransCore

/// The icon in the menu bar while a transcription runs: the mark of the app icon in lines, a sound wave on the left that
/// runs into the middle and calms down there, and the word's line on the right. The icon does not move. While Slovo
/// works the line is dashed, as if not written yet; at the end the icon shows the line whole (or a cross in its place when
/// the transcription failed) for a moment and goes away. A click brings the window forward, a right or Control click opens
/// a menu: stop recognition, then the tail every app of the family has (Settings, updates, About, Quit). Drawn in code as
/// a template image like the menu bar icons of the author's other apps, the mark alone without the squircle: 17 × 22 pt,
/// the mark 16 pt across, as big as the menu bar's own icons (Wi-Fi, Control Center), 1.36 pt lines with round ends.
@MainActor
final class MenuBarIcon: NSObject {
    /// What the icon shows.
    enum Glyph: Equatable, CaseIterable {
        /// The line is dashed: the word is not written yet.
        case working
        /// The line is whole.
        case done
        /// A cross takes the line's place.
        case failed
    }

    static let defaultsKey = "menuBarIcon"

    private let transcriber: Transcriber
    private var item: NSStatusItem?
    private var ending: DispatchWorkItem?
    private var subscriptions: Set<AnyCancellable> = []
    private var shown: Glyph?
    private var showingMenu = false
    private var images: [Glyph: NSImage] = [:]

    init(transcriber: Transcriber) {
        self.transcriber = transcriber
        super.init()
        transcriber.$phase.removeDuplicates().sink { [weak self] phase in
            // @Published sends before the value changes: read it on the next turn.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.phaseChanged(to: phase) } }
        }.store(in: &subscriptions)
        transcriber.$step.combineLatest(transcriber.$stepProgress).sink { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshTooltip() } }
        }.store(in: &subscriptions)
        transcriber.$menuBarIcon.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.phaseChanged(to: transcriber.phase) } }
        }.store(in: &subscriptions)
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
            item.button?.action = #selector(clicked)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.imagePosition = .imageOnly
            self.item = item
        }
        draw(.working)
        refreshTooltip()
    }

    /// The whole line or the cross for 1.5 s, then away.
    private func finish(_ glyph: Glyph) {
        draw(glyph)
        setTooltip(glyph == .done ? L("Расшифровка готова") : L("Не получилось"))
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        ending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func hide() {
        ending?.cancel()
        ending = nil
        shown = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func draw(_ glyph: Glyph) {
        guard glyph != shown, let button = item?.button else { return }
        shown = glyph
        button.image = image(for: glyph)
    }

    // MARK: - Clicks and the menu

    /// The left click brings the window forward; the right click and Control-click open the menu.
    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            MainWindow.show()
        }
    }

    /// Shown the status item's own way: the menu is set for the click only, so the left click goes on to the action.
    private func showMenu() {
        guard !showingMenu, let item, let button = item.button else { return }
        showingMenu = true
        defer { showingMenu = false }
        item.menu = makeMenu()
        button.performClick(nil)
        item.menu = nil
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        // The icon stays for a moment after the end: there is nothing to stop then.
        let stop = ClosureMenuItem(L("Остановить распознавание")) { [weak self] in self?.transcriber.cancel() }
        stop.isEnabled = transcriber.phase == .working
        menu.addItem(stop)
        menu.addItem(.separator())
        menu.addItem(entry(L("Настройки…"), key: ",") { [weak self] in self?.openSettings() })
        let updates = entry(L("Проверить обновления…")) { [weak self] in
            Updater.slovo.check(userInitiated: true)
            self?.openSettings()
        }
        updates.isEnabled = !Updater.slovo.isBusy
        menu.addItem(updates)
        menu.addItem(entry(L("О приложении «Slovo»")) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        menu.addItem(.separator())
        menu.addItem(entry(L("Завершить Slovo"), key: "q") { NSApp.terminate(nil) })
        return menu
    }

    private func entry(_ title: String, key: String = "", _ handler: @escaping () -> Void) -> ClosureMenuItem {
        let entry = ClosureMenuItem(title, handler: handler)
        entry.keyEquivalent = key
        return entry
    }

    /// Settings in front: the window that is open, or the main window opens it (only views can open windows).
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.contains("settings") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            transcriber.settingsRequests += 1
        }
    }

    // MARK: - Tooltip

    /// The tooltip while Slovo works: what is going on, and how far.
    private func refreshTooltip() {
        guard item != nil, ending == nil, transcriber.phase == .working else { return }
        setTooltip(tooltipText())
    }

    private func setTooltip(_ text: String) {
        guard let button = item?.button, button.toolTip != text else { return }
        button.toolTip = text
        button.setAccessibilityLabel(text)
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

    /// The image: 17 × 22 pt. 22 pt is the height of the menu bar's own items; the width is the mark's 16 pt with half a
    /// point to spare on each side, as the 15 pt canvas had around the 14 pt mark. The status item is `variableLength`:
    /// as wide as the image plus the menu bar's own margins.
    nonisolated static let canvas = NSSize(width: 17, height: 22)

    /// Where the mark lies, in points of the canvas (y down). Like the app icon's mark it is split in the middle of the
    /// image: the wave on the left half, from `waveLeft`, runs into one point at `middle`, and the line goes on to
    /// `lineEnd`, all along the axis (see `axis`). With its round ends the mark is `markWidth` across, and the swing is as
    /// tall for its length as in the icon. The mark as it was at 20 pt across, with 1.7 pt lines, scaled by 16 / 20 (and
    /// before that scaled up from 14 pt with 1.18 pt lines): the lines and the swing shrink with it.
    enum Layout {
        static let markWidth: CGFloat = 16
        /// The thickness of the lines, in the same proportion to the mark as before: 1.7 pt on 20, 1.18 on 14.
        static let lineWidth: CGFloat = 1.36
        static let waveLeft = (MenuBarIcon.canvas.width - markWidth + lineWidth) / 2
        static let middle = MenuBarIcon.canvas.width / 2
        static let lineEnd = MenuBarIcon.canvas.width - waveLeft
        /// How far the wave swings at the left end.
        static let amplitude: CGFloat = 4
        /// A wave and a quarter fit between the left end and the middle.
        static let cycles: CGFloat = 1.25
        /// The side of the cross that takes the line's place when the transcription fails.
        static let cross: CGFloat = 4
        /// While the word is not written yet the line is dashed, in the same black and as thick as the whole line: this
        /// many dashes between the middle and the line's end.
        static let dashes = 3
        /// The break between two dashes, from the end of one round cap to the start of the next: a line's thickness.
        static let dashBreak = lineWidth
        /// The length of a dash between the centres of its round caps, such that the dashes and the breaks between them
        /// fill the line from `middle` to `lineEnd` exactly.
        static let dashLength = (lineEnd - middle - CGFloat(dashes - 1) * (dashBreak + lineWidth)) / CGFloat(dashes)

        /// The axis: the middle of the height, moved to where the line covers whole pixels at `scale` as far as it
        /// can, onto a boundary between pixel rows when the line is an even number of pixels thick, into the middle of
        /// a row when it is odd.
        static func axis(scale: CGFloat) -> CGFloat {
            let middle = MenuBarIcon.canvas.height / 2
            guard scale > 0 else { return middle }
            let pixels = max(1, (lineWidth * scale).rounded())
            let offset: CGFloat = pixels.truncatingRemainder(dividingBy: 2) == 1 ? 0.5 : 0
            return ((middle * scale - offset).rounded(.down) + offset) / scale
        }
    }

    /// At rest the wave lies as the app icon's does: it leaves the axis upwards.
    nonisolated static let restingPhase = CGFloat.pi

    /// The image of a glyph, drawn once for each pixel density it is shown at. Made once: the glyphs do not move.
    private func image(for glyph: Glyph) -> NSImage {
        if let image = images[glyph] { return image }
        let image = NSImage(size: Self.canvas, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            MenuBarIcon.draw(glyph, in: ctx)
            return true
        }
        image.isTemplate = true
        images[glyph] = image
        return image
    }

    /// Draws a glyph on the canvas (y down): black lines with round ends, the line dashed while the word is not written yet.
    nonisolated static func draw(_ glyph: Glyph, in ctx: CGContext) {
        // The image is drawn once for each pixel density, so the line lands on whole pixels at 1x and at 2x.
        let scale = abs(ctx.userSpaceToDeviceSpaceTransform.a)
        let y = Layout.axis(scale: scale)
        ctx.setLineWidth(Layout.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        func stroke(_ points: [CGPoint], dashed: Bool = false) {
            ctx.setStrokeColor(NSColor.black.cgColor)
            // Dashes begin at the first point, so the first one grows out of the wave and the last one ends at `lineEnd`.
            ctx.setLineDash(phase: 0, lengths: dashed ? [Layout.dashLength, Layout.dashBreak + Layout.lineWidth] : [])
            ctx.addLines(between: points)
            ctx.strokePath()
        }
        stroke(wave(phase: restingPhase, axis: y))
        switch glyph {
        case .failed:
            // A cross in the place of the line, at its far end, clear of the wave.
            let right = Layout.lineEnd, left = right - Layout.cross, top = y - Layout.cross / 2, bottom = y + Layout.cross / 2
            stroke([CGPoint(x: left, y: top), CGPoint(x: right, y: bottom)])
            stroke([CGPoint(x: right, y: top), CGPoint(x: left, y: bottom)])
        case .working:
            stroke([CGPoint(x: Layout.middle, y: y), CGPoint(x: Layout.lineEnd, y: y)], dashed: true)
        case .done:
            stroke([CGPoint(x: Layout.middle, y: y), CGPoint(x: Layout.lineEnd, y: y)])
        }
    }

    /// A wave like those of the app icon: its swing holds on the left and fades out towards the middle, where the wave
    /// lies down on the axis and goes on as the line.
    nonisolated static func wave(phase: CGFloat, axis: CGFloat) -> [CGPoint] {
        (0...40).map { i in
            let t = CGFloat(i) / 40
            return CGPoint(x: Layout.waveLeft + (Layout.middle - Layout.waveLeft) * t,
                           y: axis + Layout.amplitude * pow(cos(.pi / 2 * t), 1.6) * sin(2 * .pi * Layout.cycles * t + phase))
        }
    }
}
