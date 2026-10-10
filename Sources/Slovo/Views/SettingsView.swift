import SwiftUI
import AppKit
import TransCore

/// Settings (⌘,), in cards: the language of the interface, opening at login, the sounds and the menu bar icon, then the
/// updates, then recognition (the model and the language of the speech, silence, accurate mode), the names and terms
/// for Whisper, and the way to the models.
struct SettingsView: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: Layout.spacing) {
            VStack(spacing: 0) {
                InterfaceLanguageRows()
                LoginItemRows()
                SettingRow(title: L("Звуковые эффекты"),
                           help: L("Slovo коротко звучит, когда расшифровка началась, закончилась или не удалась, когда текст скопирован, сохранён или отправлен, модель скачана или удалена и когда обновление не установилось. Громкость как у предупреждений macOS. Если в Системных настройках, раздел «Звук», выключены звуковые эффекты интерфейса, звуков нет")) {
                    Switch(isOn: $transcriber.soundEffects)
                }
                SettingRow(title: L("Значок в строке меню во время работы"),
                           help: L("Пока идёт расшифровка, в строке меню виден значок Slovo. Щелчок по нему открывает окно, правый щелчок открывает меню"),
                           last: true) {
                    Switch(isOn: $transcriber.menuBarIcon)
                }
            }
            .card()

            VStack(spacing: 0) {
                UpdateSettingRows()
            }
            .card()

            VStack(spacing: 0) {
                SettingRow(title: L("Модель")) { ModelCapsule() }
                SettingRow(title: L("Язык речи")) { LanguageCapsule() }
                SettingRow(title: L("Пропуск тишины"),
                           help: L("Whisper не придумывает фразы там, где никто не говорит. Если пропадают тихие реплики, выключите пропуск тишины")) {
                    Switch(isOn: $transcriber.skipSilence)
                }
                SettingRow(title: L("Точный режим"),
                           help: L("Whisper перебирает несколько вариантов каждой фразы: ошибок меньше, но распознавание медленнее"),
                           last: true) {
                    Switch(isOn: $transcriber.beamSearch)
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Имена и термины"))
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                TextField("", text: $transcriber.prompt, prompt: Text(L("Например: Сбербанк, Kubernetes, Анна Ковальчук")), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(2...4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.control))
            }
            .padding(12)
            .card()
            .help(L("Перечислите слова из записей, и Whisper будет писать их правильно"))

            HStack {
                Button(L("Модели распознавания…")) { openWindow(id: "models") }
                    .appButton(.secondary)
                    .controlSize(.small)
                Spacer(minLength: 0)
            }
        }
        .padding([.horizontal, .bottom], Layout.padding)
        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .blackWindow(title: L("Настройки"))
        .onAppear { modelStore.refresh() }
    }
}

/// The settings row for the language of the interface and, once the choice differs from the language Slovo runs in, the
/// way to restart. The choice is the app's own `AppleLanguages` (`InterfaceLanguage`), the same list System Settings,
/// Language & Region, Applications writes, so it is read again when Settings open and when the user comes back to Slovo.
struct InterfaceLanguageRows: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var updater: Updater
    @State private var choice = InterfaceLanguage.saved()
    @State private var needsRestart = InterfaceLanguage.needsRestart(running: Localization.current)

    var body: some View {
        SettingRow(title: L("Язык интерфейса"),
                   help: L("При варианте «Как в системе» Slovo берёт первый подходящий язык из списка в Системных настройках, раздел «Язык и регион». Новый язык включится после перезапуска")) {
            MenuCapsule(title: name(of: choice), help: L("Язык интерфейса")) { menu() }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        if needsRestart {
            let busy = updater.appIsBusy()
            HStack(spacing: 8) {
                Text(L("Язык сменится после перезапуска"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Button(L("Перезапустить")) { InterfaceLanguage.relaunch() }
                    .appButton(.secondary)
                    .controlSize(.small)
                    .disabled(busy)
                    .help(busy ? L("Slovo перезапустится, когда закончится расшифровка или загрузка модели и готовый текст будет сохранён или скопирован") : "")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .overlay(alignment: .bottom) { RowDivider() }
        }
    }

    /// The choices name the languages in their own words, so a wrong pick can be undone in any interface language.
    private func name(of language: InterfaceLanguage) -> String {
        switch language {
        case .system: return L("Как в системе")
        case .russian: return "Русский"
        case .english: return "English"
        }
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        for language in InterfaceLanguage.allCases {
            menu.addItem(ClosureMenuItem(name(of: language), checked: language == choice) {
                InterfaceLanguage.save(language)
                refresh()
            })
        }
        return menu
    }

    private func refresh() {
        choice = InterfaceLanguage.saved()
        needsRestart = InterfaceLanguage.needsRestart(running: Localization.current)
    }
}
