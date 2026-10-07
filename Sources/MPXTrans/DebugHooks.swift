import SwiftUI
import AppKit
import TransCore

/// Test hooks driven by environment variables (used for automated UI checks):
///   MPXTRANS_OPEN=<file>                            recognize a file at launch
///   MPXTRANS_ACTIONS="2:format=srt;3:dark"          run actions after N seconds (see `perform`)
///   MPXTRANS_SNAPSHOTS="3:/tmp/a.png;9:/tmp/b.png"  save window snapshots after N seconds
///   MPXTRANS_QUIT_AFTER=<seconds>
@MainActor
enum DebugHooks {
    static weak var transcriber: Transcriber?

    /// Simulated drag over the window (a real drag cannot be scripted).
    final class State: ObservableObject {
        static let shared = State()
        @Published var dropTargeted = false
    }

    nonisolated static func install() {
        let env = ProcessInfo.processInfo.environment
        // A relaunched copy of the app inherits the environment and must not repeat the test actions.
        for name in ["MPXTRANS_OPEN", "MPXTRANS_ACTIONS", "MPXTRANS_SNAPSHOTS", "MPXTRANS_QUIT_AFTER"] { unsetenv(name) }
        if let path = env["MPXTRANS_OPEN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                MainActor.assumeIsolated { transcriber?.open(URL(fileURLWithPath: path)) }
            }
        }
        for (delay, value) in schedule(env["MPXTRANS_ACTIONS"]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { perform(value) } }
        }
        for (delay, value) in schedule(env["MPXTRANS_SNAPSHOTS"]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { snapshot(to: value) } }
        }
        if let quit = env["MPXTRANS_QUIT_AFTER"].flatMap(Double.init) {
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

    /// Saves every visible window (main window as given, others with a suffix). `screencapture` shows the real
    /// glass; when it is not allowed to record the screen, the view hierarchy is drawn instead (without glass).
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
        case "models": transcriber.modelManagerRequested = true
        case "settings": NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case "cancel": transcriber.cancel()
        case "reset": transcriber.reset()
        case "rerun": transcriber.retranscribe()
        case "open": transcriber.open(URL(fileURLWithPath: value))
        case "copy": transcriber.copyText()
        case "save": transcriber.write(to: URL(fileURLWithPath: value))
        case "edit": transcriber.texts[transcriber.format, default: ""] += value
        case "target": State.shared.dropTargeted = value != "0"
        case "activate":
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
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
                "text": transcriber.currentText,
                "words": transcriber.wordCountText,
                "pasteboard": NSPasteboard.general.string(forType: .string) ?? "",
                "windows": NSApp.windows.filter(\.isVisible).map { ["id": $0.windowNumber, "title": $0.title, "frame": "\($0.frame)"] },
            ]
            if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: value))
            }
        default: break
        }
    }
}
