import SwiftUI
import AppKit
import TransCore

@main
struct MPXTransApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var transcriber = Transcriber()

    init() {
        Localization.apply()
    }

    var body: some Scene {
        Window("MPXTrans", id: "main") {
            ContentView()
                .environmentObject(transcriber)
                .environmentObject(transcriber.modelStore)
                .frame(minWidth: 400, minHeight: 470)
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
        .defaultSize(width: 600, height: 640)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(transcriber)
                .environmentObject(transcriber.modelStore)
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var transcriber: Transcriber
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
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
