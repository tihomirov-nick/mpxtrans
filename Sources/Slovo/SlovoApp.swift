import SwiftUI
import AppKit
import Combine
import TransCore

@main
struct SlovoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Made on first use, after `init` has carried over the settings of MPXTrans. The app delegate wires both up at launch,
    // with or without the window.
    @StateObject private var transcriber = Transcriber.shared
    @StateObject private var updater = Updater.slovo

    init() {
        LegacySettings.migrate()
        Localization.apply()
    }

    var body: some Scene {
        Window("Slovo", id: "main") {
            ContentView()
                .environmentObject(transcriber)
                .environmentObject(transcriber.modelStore)
                .environmentObject(updater)
                .frame(minWidth: 400, minHeight: 440)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 470, height: 580)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(transcriber: transcriber, updater: updater)
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
                .environmentObject(updater)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 606)
        .windowResizability(.contentMinSize)
    }
}

extension Updater {
    /// New versions from the releases on GitHub. `SLOVO_UPDATE_API` points to another server (for tests).
    static let slovo = Updater(repo: "tihomirov-nick/slovo",
                               apiBase: ProcessInfo.processInfo.environment["SLOVO_UPDATE_API"]
                                   .flatMap(URL.init(string:)) ?? URL(string: "https://api.github.com")!)
}

struct AppCommands: Commands {
    @ObservedObject var transcriber: Transcriber
    @ObservedObject var updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            // Settings show what the check found: the version and "up to date", or an error.
            Button(L("Проверить обновления…")) {
                updater.check(userInitiated: true)
                openWindow(id: "settings")
            }
            .disabled(updater.isBusy)
        }
        CommandGroup(replacing: .appSettings) {
            Button(L("Настройки…")) { openWindow(id: "settings") }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button(L("Открыть файл…")) { transcriber.showOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(transcriber.isUpdating)
            Button(L("Новая расшифровка")) { transcriber.reset() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(transcriber.phase == .idle)
        }
        CommandGroup(replacing: .saveItem) {
            // The system's "Close" belongs to the same group: replacing it takes ⌘W away, so it is put back.
            Button(L("Закрыть")) { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
            Divider()
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
            Menu(L("Регистр и знаки")) {
                ForEach(TextCaseMode.allCases) { mode in
                    Toggle(mode.title, isOn: Binding(
                        get: { transcriber.caseMode == mode },
                        set: { if $0 { transcriber.caseMode = mode } }
                    ))
                }
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

/// The main window and the Dock icon. Started at login, or brought back quietly by an update that installed itself while
/// Slovo ran in the background, Slovo runs with neither: it only checks for updates and installs them. Opening Slovo
/// from the Dock, Launchpad or Finder, a file opened with Slovo and a transcription that starts bring both back.
@MainActor
enum MainWindow {
    /// Running without the window and the Dock icon.
    private(set) static var inBackground = false

    static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true }
    }

    /// While the app launches, before its windows open.
    static func startInBackground() {
        inBackground = true
        NSApp.setActivationPolicy(.accessory)
    }

    /// SwiftUI opens the main window by itself, before applicationDidFinishLaunching: in the background it goes away
    /// there, before it is drawn. A window that comes later goes away in `BlackWindow`.
    static func hideWindows() {
        guard inBackground else { return }
        for window in NSApp.windows where window.isVisible {
            window.orderOut(nil)
        }
    }

    /// The window in front, with the Dock icon and the menu bar. Without models the models window opens too, as at
    /// a usual launch.
    static func show() {
        if inBackground {
            inBackground = false
            NSApp.setActivationPolicy(.regular)
            if !Transcriber.shared.modelStore.hasAnyModel { Transcriber.shared.modelManagerRequested = true }
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var attached = false
    private var pendingURL: URL?
    private var menuBarIcon: MenuBarIcon?
    private var subscriptions: [AnyCancellable] = []
    /// The quit waits until then: "Обновляюсь до версии…" stays in the window for a moment before an update that
    /// installed itself restarts Slovo.
    private var restartNoticeEnd: Date?

    /// Slovo is black in the light theme as well, like FaceID's island; menus, alerts and panels follow. Started at
    /// login, it runs in the background (`MainWindow`).
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if Updater.LoginItem.launchedAtLogin { MainWindow.startInBackground() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainWindow.hideWindows()
        let transcriber = Transcriber.shared
        let updater = Updater.slovo
        attach(transcriber)
        DebugHooks.transcriber = transcriber
        connect(transcriber, updater)
        updater.start()
        DebugHooks.install()
    }

    private func attach(_ transcriber: Transcriber) {
        attached = true
        menuBarIcon = MenuBarIcon(transcriber: transcriber)
        if let url = pendingURL {
            pendingURL = nil
            transcriber.open(url)
        }
        // A file that came during the update, before this launch.
        transcriber.openFileLeftForUpdate()
    }

    private func connect(_ transcriber: Transcriber, _ updater: Updater) {
        // An update that installs itself restarts Slovo only when that loses nothing: no transcription, no transcript that
        // only the window holds, no model download, no open panel or sheet.
        updater.appIsBusy = { [weak transcriber] in
            transcriber?.holdsWork == true || NSApp.modalWindow != nil || NSApp.windows.contains { $0.attachedSheet != nil }
        }
        // A transcription, or an edit of a transcript already saved, stops the download of an update started with
        // "Update" (the offer stays), so that the restart after it loses nothing.
        transcriber.$phase.removeDuplicates().sink { [weak updater] phase in
            guard phase == .working else { return }
            if case .downloading = updater?.state { updater?.cancel() }
            if MainWindow.inBackground { MainWindow.show() }
        }.store(in: &subscriptions)
        transcriber.$resultTaken.removeDuplicates().sink { [weak transcriber, weak updater] taken in
            guard !taken, transcriber?.phase == .done, case .downloading = updater?.state else { return }
            updater?.cancel()
        }.store(in: &subscriptions)
        updater.$state.removeDuplicates().sink { [weak transcriber] state in
            if case .failed(_, .some) = state { SoundEffects.play(.failure) }
            var installing = false
            if case .installing = state { installing = true }
            if transcriber?.isUpdating != installing { transcriber?.isUpdating = installing }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: Updater.willRestart).sink { [weak self] note in
            guard note.userInfo?["automatic"] as? Bool == true, !MainWindow.inBackground,
                  MainWindow.window?.isVisible == true else { return }
            self?.restartNoticeEnd = Date().addingTimeInterval(1.5)
        }.store(in: &subscriptions)
    }

    /// Slovo opened from the Dock, Launchpad or Finder while it runs: the window comes back, from the background too.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let window = MainWindow.window
        guard MainWindow.inBackground || window?.isVisible == false else { return true }
        MainWindow.show()
        // No window to bring back: SwiftUI opens a new one.
        return window == nil
    }

    /// Files dropped onto the Dock icon or opened with "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainWindow.show()
        if attached {
            Transcriber.shared.open(url)
        } else {
            pendingURL = url
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A running job is cancelled first. whisper.cpp keeps its GPU buffers until the job returns, and ggml aborts
    /// when the process exits before that (it frees its Metal devices on exit), so the app quits once the job stops.
    /// Before an update that installed itself restarts Slovo, the window shows it for a moment.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if attached { Transcriber.shared.cancel() }
        let notice = max(0, restartNoticeEnd?.timeIntervalSinceNow ?? 0)
        restartNoticeEnd = nil
        guard WhisperEngine.isBusy || notice > 0 else { return .terminateNow }
        DispatchQueue.global(qos: .userInitiated).async {
            if notice > 0 { Thread.sleep(forTimeInterval: notice) }
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

    /// Stops ffmpeg if it is still extracting audio.
    func applicationWillTerminate(_ notification: Notification) {
        if attached { Transcriber.shared.cancel() }
    }
}
