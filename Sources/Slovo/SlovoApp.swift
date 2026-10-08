import SwiftUI
import AppKit
import TransCore

@main
struct SlovoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var transcriber = Transcriber()

    init() {
        LegacySettings.migrate()
        Localization.apply()
    }

    var body: some Scene {
        Window("Slovo", id: "main") {
            ContentView()
                .environmentObject(transcriber)
                .environmentObject(transcriber.modelStore)
                .frame(minWidth: 400, minHeight: 440)
                .onAppear {
                    appDelegate.attach(transcriber)
                    DebugHooks.transcriber = transcriber
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 470, height: 580)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(transcriber: transcriber)
        }

        Window(L("Модели распознавания"), id: "models") {
            ModelManagerView()
                .environmentObject(transcriber)
                .environmentObject(transcriber.modelStore)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 560, height: 425)
        .windowResizability(.contentMinSize)

        // A window of its own rather than the Settings scene, and sized by default rather than to its content:
        // on macOS 26 a window sized to its content (the Settings window is one) gets its content above the title
        // bar, which hides the window buttons.
        Window(L("Настройки"), id: "settings") {
            SettingsView()
                .environmentObject(transcriber)
                .environmentObject(transcriber.modelStore)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 324)
        .windowResizability(.contentMinSize)
    }
}

struct AppCommands: Commands {
    @ObservedObject var transcriber: Transcriber
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(L("Настройки…")) { openWindow(id: "settings") }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button(L("Открыть файл…")) { transcriber.showOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button(L("Новая расшифровка")) { transcriber.reset() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(transcriber.phase == .idle)
        }
        CommandGroup(replacing: .saveItem) {
            Button(L("Сохранить…")) { transcriber.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(transcriber.phase != .done)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button(L("Скопировать весь текст")) { transcriber.copyText() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(transcriber.phase != .done)
        }
        CommandMenu(L("Расшифровка")) {
            ForEach(Array(TranscriptFormat.allCases.enumerated()), id: \.element) { index, format in
                Toggle(format.title, isOn: Binding(
                    get: { transcriber.format == format },
                    set: { if $0 { transcriber.format = format } }
                ))
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            Button(L("Распознать заново")) { transcriber.retranscribe() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(transcriber.phase != .done)
            Button(L("Остановить распознавание")) { transcriber.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(transcriber.phase != .working)
            Divider()
            Button(L("Модели распознавания…")) { openWindow(id: "models") }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var transcriber: Transcriber?
    private var pendingURL: URL?

    @MainActor
    func attach(_ transcriber: Transcriber) {
        self.transcriber = transcriber
        if let url = pendingURL {
            pendingURL = nil
            transcriber.open(url)
        }
    }

    /// Files dropped onto the Dock icon or opened with "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated {
            if let transcriber {
                transcriber.open(url)
            } else {
                pendingURL = url
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A running job is cancelled first. whisper.cpp keeps its GPU buffers until the job returns, and ggml aborts
    /// when the process exits before that (it frees its Metal devices on exit), so the app quits once the job stops.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { transcriber?.cancel() }
        guard WhisperEngine.isBusy else { return .terminateNow }
        DispatchQueue.global(qos: .userInitiated).async {
            WhisperEngine.waitUntilIdle(timeout: 10)
            // While it waits for the reply, AppKit runs the main run loop in the modal panel mode, where blocks
            // sent to the main queue do not run.
            RunLoop.main.perform(inModes: [.default, .modalPanel]) {
                MainActor.assumeIsolated { NSApp.reply(toApplicationShouldTerminate: true) }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        return .terminateLater
    }

    /// Slovo is black in the light theme as well, like FaceID's island; menus, alerts and panels follow.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugHooks.install()
    }

    /// Stops ffmpeg if it is still extracting audio.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            transcriber?.cancel()
        }
    }
}
