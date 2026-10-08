import SwiftUI
import AppKit
import TransCore

/// Test hooks driven by environment variables (used for automated UI checks):
///   SLOVO_OPEN=<file>                               recognize a file at launch
///   SLOVO_ACTIONS="2:format=srt;3:rerun-panel"      run actions after N seconds (see `perform`)
///   SLOVO_SNAPSHOTS="3:/tmp/a.png;9:/tmp/b.png"     save window snapshots after N seconds
///   SLOVO_QUIT_AFTER=<seconds>
@MainActor
enum DebugHooks {
    static weak var transcriber: Transcriber?
    static weak var updater: Updater?
    static weak var menuBarIcon: MenuBarIcon?

    /// Simulated drag over the window (a real drag cannot be scripted), and the panel for another pass.
    final class State: ObservableObject {
        static let shared = State()
        @Published var dropTargeted = false
        @Published var rerunPanel = false
        /// A window to open ("settings", "models"): only views can open windows.
        @Published var openWindow: String?
        /// What the "copy" action copied.
        var copiedText = ""
        /// Sound effects played since launch.
        var sounds: [String] = []
    }

    nonisolated static func install() {
        let env = ProcessInfo.processInfo.environment
        // A relaunched copy of the app inherits the environment and must not repeat the test actions.
        for name in ["SLOVO_OPEN", "SLOVO_ACTIONS", "SLOVO_SNAPSHOTS", "SLOVO_QUIT_AFTER"] { unsetenv(name) }
        if let path = env["SLOVO_OPEN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                MainActor.assumeIsolated { transcriber?.open(URL(fileURLWithPath: path)) }
            }
        }
        for (delay, value) in schedule(env["SLOVO_ACTIONS"]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { perform(value) } }
        }
        for (delay, value) in schedule(env["SLOVO_SNAPSHOTS"]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { snapshot(to: value) } }
        }
        if let quit = env["SLOVO_QUIT_AFTER"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + quit) { NSApp.terminate(nil) }
        }
    }

    nonisolated static func schedule(_ text: String?) -> [(Double, String)] {
        (text ?? "").split(separator: ";").compactMap { item in
            let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let delay = Double(parts[0]) else { return nil }
            return (delay, parts[1])
        }
    }

    /// Saves every visible window (main window as given, others with a suffix). `screencapture` shows the window as
    /// it is on screen; when it is not allowed to record the screen, the view hierarchy is drawn instead.
    static func snapshot(to path: String) {
        for (index, window) in NSApp.windows.filter(\.isVisible).enumerated() {
            let suffix = index == 0 ? "" : "-\(index)"
            let url = URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "\(suffix).png"))
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
            try? capture.run()
            capture.waitUntilExit()
            if capture.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) { continue }
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    static func perform(_ action: String) {
        guard let transcriber else { return }
        let parts = action.split(separator: "=", maxSplits: 1).map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "format":
            if let format = TranscriptFormat(rawValue: value) { transcriber.format = format }
        case "language": transcriber.language = value
        case "model": transcriber.modelID = value
        case "models": State.shared.openWindow = "models"
        case "settings": State.shared.openWindow = "settings"
        case "cancel": transcriber.cancel()
        case "reset": transcriber.reset()
        case "rerun": transcriber.retranscribe()
        case "open": transcriber.open(URL(fileURLWithPath: value))
        case "copy":
            // Into a pasteboard of its own: tests run on a real Mac, and the user's clipboard stays as it was.
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.slovo.debug"))
            transcriber.copyText(to: pasteboard)
            State.shared.copiedText = pasteboard.string(forType: .string) ?? ""
            pasteboard.releaseGlobally()
        case "save": transcriber.write(to: URL(fileURLWithPath: value))
        case "edit": transcriber.texts[transcriber.format, default: ""] += value
        case "case":
            if let mode = TextCaseMode(rawValue: value) { transcriber.caseMode = mode }
        case "select":
            // select=<location>,<length> in the transcript, in UTF-16 units; select=end puts the cursor at the end
            let numbers = value.split(separator: ",").compactMap { Int($0) }
            if let textView = transcriptTextView() {
                let length = (textView.string as NSString).length
                let location = value == "end" ? length : min(numbers.first ?? 0, length)
                textView.setSelectedRange(NSRange(location: location, length: min(numbers.count > 1 ? numbers[1] : 0, length - location)))
            }
        case "type":
            // Typed into the transcript at the selection, the way the keyboard types
            transcriptTextView()?.insertText(value, replacementRange: NSRange(location: NSNotFound, length: 0))
        case "undo": transcriptTextView()?.undoManager?.undo()
        case "revert": transcriber.revertEdits()
        case "scroll":
            // scroll=<y> of the transcript, in points
            if let clipView = transcriptTextView()?.enclosingScrollView?.contentView, let y = Double(value) {
                clipView.scroll(to: NSPoint(x: 0, y: y))
                clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
            }
        case "download":
            if let model = ModelCatalog.model(id: value) { transcriber.modelStore.download(model) }
        case "cancel-download": transcriber.modelStore.cancelDownload(value)
        case "delete-model": transcriber.modelStore.deleteCustom(AppPaths.modelsDir.appendingPathComponent(value))
        case "update-check": updater?.check(userInitiated: value != "auto")
        case "update-install": updater?.install()
        case "update-skip": updater?.skip()
        case "update-later": updater?.dismiss()
        case "update-cancel": updater?.cancel()
        case "menu":
            // menu=<title>: chooses the item of the app menu or the File menu, as a click does
            for menu in NSApp.mainMenu?.items.prefix(2).compactMap(\.submenu) ?? [] {
                menu.delegate?.menuNeedsUpdate?(menu)
                if let index = menu.items.firstIndex(where: { $0.title == value }) { menu.performActionForItem(at: index) }
            }
        case "simulate-work": transcriber.simulateWork(file: URL(fileURLWithPath: value))
        case "updating":
            // updating=1|0: as while an update is installed (files wait, opening is off)
            transcriber.isUpdating = value == "1"
        case "menubar-frames":
            // menubar-frames=<folder>: the glyph's frames as PNG, 16 pt at 2x and enlarged 8x
            MenuBarIcon.saveFrames(to: URL(fileURLWithPath: value))
        case "target": State.shared.dropTargeted = value != "0"
        case "rerun-panel": State.shared.rerunPanel = value != "0"
        case "activate":
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
        case "size":
            // size=<width>x<height> of the main window's content
            let numbers = value.split(separator: "x").compactMap { Double($0) }
            if numbers.count == 2, let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) ?? NSApp.windows.first {
                window.setContentSize(NSSize(width: numbers[0], height: numbers[1]))
            }
        case "report":
            // report=<path>: state and window ids as JSON (for screenshots with `screencapture -l`)
            let info: [String: Any] = [
                "phase": "\(transcriber.phase)",
                "step": "\(transcriber.step)",
                "progress": transcriber.stepProgress ?? -1,
                "modelID": transcriber.modelID,
                "language": transcriber.language,
                "format": transcriber.format.rawValue,
                "caseMode": transcriber.caseMode.rawValue,
                "text": transcriber.currentText,
                "shownInView": transcriptTextView()?.string ?? "",
                "selection": transcriptTextView().map { NSStringFromRange($0.selectedRange()) } ?? "",
                "scroll": transcriptTextView()?.enclosingScrollView.map { $0.contentView.bounds.origin.y } ?? -1,
                "source": transcriber.texts[transcriber.format] ?? "",
                "edited": transcriber.isEdited,
                "words": transcriber.wordCountText,
                "copied": State.shared.copiedText,
                "sounds": State.shared.sounds,
                "update": updater.map { "\($0.state)" } ?? "",
                "version": updater?.currentVersion ?? "",
                "menuBarIcon": menuBarIcon?.screenFrame.map { NSStringFromRect($0) } ?? "",
                "menuBarTooltip": menuBarIcon?.tooltip ?? "",
                "menus": (NSApp.mainMenu?.items.prefix(2).compactMap(\.submenu) ?? []).flatMap { menu -> [String] in
                    // As when the menu opens: SwiftUI brings the items up to date then.
                    menu.delegate?.menuNeedsUpdate?(menu)
                    menu.update()
                    return menu.items.filter { !$0.isSeparatorItem }.map { "\($0.title)=\($0.isEnabled)" }
                },
                "updating": transcriber.isUpdating,
                "fileLeftForUpdate": UserDefaults.standard.string(forKey: "openAfterUpdate") ?? "",
                "windows": NSApp.windows.filter(\.isVisible).map { ["id": $0.windowNumber, "title": $0.title, "frame": "\($0.frame)"] },
            ]
            if JSONSerialization.isValidJSONObject(info),
               let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: value))
            } else {
                try? "\(info)".write(toFile: value + ".txt", atomically: true, encoding: .utf8)
            }
        default: break
        }
    }

    /// The editable text of the result in the main window.
    private static func transcriptTextView() -> NSTextView? {
        func find(in view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView, textView.isEditable { return textView }
            for subview in view.subviews {
                if let found = find(in: subview) { return found }
            }
            return nil
        }
        return NSApp.windows.filter(\.isVisible).lazy.compactMap { $0.contentView.flatMap(find) }.first
    }
}
