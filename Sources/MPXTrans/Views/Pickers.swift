import SwiftUI
import AppKit
import TransCore

/// Languages outside the short list, for the "Other languages" submenu.
private let otherLanguages = WhisperEngine.allLanguages.filter { !WhisperEngine.commonLanguageCodes.contains($0.code) }

/// Short name for a glass capsule: "Авто" instead of "Определить автоматически".
private func shortLanguageName(_ code: String) -> String {
    code == "auto" ? L("Авто") : WhisperEngine.languageName(code)
}

/// Glass capsule with the recognition model; the menu lists the installed models.
struct ModelMenu: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GlassMenuButton(systemImage: "cpu", title: modelStore.hasAnyModel ? transcriber.modelName : L("Скачать модель")) {
            let menu = NSMenu()
            for id in modelStore.availableModelIDs {
                menu.addItem(ClosureMenuItem(modelStore.displayName(for: id), checked: id == transcriber.modelID) {
                    transcriber.modelID = id
                })
            }
            if !modelStore.availableModelIDs.isEmpty { menu.addItem(.separator()) }
            let openWindow = self.openWindow
            menu.addItem(ClosureMenuItem(L("Скачать другие модели…")) { openWindow(id: "models") })
            return menu
        }
        .help(L("Модель распознавания"))
    }
}

/// Glass capsule with the language of the speech.
struct LanguageMenu: View {
    @EnvironmentObject var transcriber: Transcriber

    var body: some View {
        GlassMenuButton(systemImage: "globe", title: shortLanguageName(transcriber.language)) {
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
        .help(L("Язык речи"))
    }
}

/// A glass capsule (icon, title, chevron) that opens a native menu below itself. SwiftUI menus on macOS
/// cannot be drawn as glass capsules, and the whole capsule should react to a click.
struct GlassMenuButton: View {
    let systemImage: String
    let title: String
    let makeMenu: () -> NSMenu
    @State private var anchor = ViewAnchor()

    init(systemImage: String, title: String, makeMenu: @escaping () -> NSMenu) {
        self.systemImage = systemImage
        self.title = title
        self.makeMenu = makeMenu
    }

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            let menu = makeMenu()
            let below = view.isFlipped ? view.bounds.maxY + 6 : view.bounds.minY - 6
            menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: below), in: view)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .glassButtonStyle()
        .background(AnchorView(anchor: anchor))
        .accessibilityLabel(title)
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func run() {
        handler()
    }
}

/// Model picker for forms (settings, "recognize again").
struct ModelPicker: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    var title: String = L("Модель")

    var body: some View {
        Picker(title, selection: $transcriber.modelID) {
            ForEach(modelStore.availableModelIDs, id: \.self) { id in
                Text(modelStore.displayName(for: id)).tag(id)
            }
            if modelStore.availableModelIDs.isEmpty {
                Text(L("Нет скачанных моделей")).tag(transcriber.modelID)
            }
        }
    }
}

/// Language picker for forms: the short list first, then every other language.
struct LanguagePicker: View {
    @EnvironmentObject var transcriber: Transcriber
    var title: String = L("Язык")

    var body: some View {
        Picker(title, selection: $transcriber.language) {
            Text(L("Определить автоматически")).tag("auto")
            Divider()
            ForEach(WhisperEngine.commonLanguageCodes, id: \.self) { code in
                Text(WhisperEngine.languageName(code)).tag(code)
            }
            Divider()
            ForEach(otherLanguages, id: \.code) { language in
                Text(language.name).tag(language.code)
            }
        }
    }
}

/// Round glass button that opens Settings.
struct SettingsButton: View {
    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 20, height: 20)
                }
            } else {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 20, height: 20)
                }
            }
        }
        .glassCircleButton()
        .help(L("Настройки"))
        .accessibilityLabel(L("Настройки"))
    }
}
