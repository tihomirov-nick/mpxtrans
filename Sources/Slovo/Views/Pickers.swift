import SwiftUI
import AppKit
import TransCore

/// Languages outside the short list, for the "Other languages" submenu.
private let otherLanguages = WhisperEngine.allLanguages.filter { !WhisperEngine.commonLanguageCodes.contains($0.code) }

/// Short name for a tile or a capsule: "Авто" instead of "Определить автоматически".
func shortLanguageName(_ code: String) -> String {
    code == "auto" ? L("Авто") : WhisperEngine.languageName(code)
}

/// The installed models, and a way to get more.
@MainActor
func modelMenu(transcriber: Transcriber, modelStore: ModelStore, openModels: @escaping () -> Void) -> NSMenu {
    let menu = NSMenu()
    for id in modelStore.availableModelIDs {
        menu.addItem(ClosureMenuItem(modelStore.displayName(for: id), checked: id == transcriber.modelID) {
            transcriber.modelID = id
        })
    }
    if !modelStore.availableModelIDs.isEmpty { menu.addItem(.separator()) }
    menu.addItem(ClosureMenuItem(L("Скачать другие модели…"), handler: openModels))
    return menu
}

/// Automatic detection, the short list of languages, then every other language in a submenu.
@MainActor
func languageMenu(transcriber: Transcriber) -> NSMenu {
    let menu = NSMenu()
    let selected = transcriber.language
    let choose: (String) -> Void = { code in transcriber.language = code }
    menu.addItem(ClosureMenuItem(L("Определить автоматически"), checked: selected == "auto") { choose("auto") })
    menu.addItem(.separator())
    for code in WhisperEngine.commonLanguageCodes {
        menu.addItem(ClosureMenuItem(WhisperEngine.languageName(code), checked: selected == code) { choose(code) })
    }
    menu.addItem(.separator())
    let others = NSMenuItem(title: L("Другие языки"), action: nil, keyEquivalent: "")
    let submenu = NSMenu()
    for language in otherLanguages {
        submenu.addItem(ClosureMenuItem(language.name, checked: selected == language.code) { choose(language.code) })
    }
    others.submenu = submenu
    if otherLanguages.contains(where: { $0.code == selected }) { others.state = .on }
    menu.addItem(others)
    return menu
}

/// The recognition model as a tile.
struct ModelTile: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let openWindow = self.openWindow
        MenuTile(symbol: "cpu", title: modelStore.hasAnyModel ? transcriber.shortModelName : L("Скачать модель"),
                 help: L("Модель распознавания")) {
            modelMenu(transcriber: transcriber, modelStore: modelStore) { openWindow(id: "models") }
        }
    }
}

/// The language of the speech as a tile.
struct LanguageTile: View {
    @EnvironmentObject var transcriber: Transcriber

    var body: some View {
        MenuTile(symbol: "globe", title: shortLanguageName(transcriber.language), help: L("Язык речи")) {
            languageMenu(transcriber: transcriber)
        }
    }
}

/// The recognition model as a capsule in a row.
struct ModelCapsule: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let openWindow = self.openWindow
        MenuCapsule(title: modelStore.hasAnyModel ? transcriber.shortModelName : L("Нет скачанных моделей"),
                    help: L("Модель распознавания")) {
            modelMenu(transcriber: transcriber, modelStore: modelStore) { openWindow(id: "models") }
        }
    }
}

/// The language of the speech as a capsule in a row.
struct LanguageCapsule: View {
    @EnvironmentObject var transcriber: Transcriber

    var body: some View {
        MenuCapsule(title: shortLanguageName(transcriber.language), help: L("Язык речи")) {
            languageMenu(transcriber: transcriber)
        }
    }
}

/// A row of a settings card: the name on the left, its control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var help: String?
    var last = false
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            control
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .contentShape(Rectangle())
        .help(help ?? "")
        .overlay(alignment: .bottom) {
            if !last { RowDivider() }
        }
    }
}
