import SwiftUI
import AppKit
import TransCore

/// Settings (⌘,): every recognition option, one short row each, and the names and terms for Whisper.
struct SettingsView: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: Layout.spacing) {
            VStack(spacing: 0) {
                SettingRow(title: L("Модель")) { ModelCapsule() }
                SettingRow(title: L("Язык речи")) { LanguageCapsule() }
                SettingRow(title: L("Пропуск тишины"),
                           help: L("Whisper не придумывает фразы там, где никто не говорит. Если пропадают тихие реплики, выключите")) {
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
            .help(L("Слова, которые встречаются в записях: Whisper будет писать их правильно"))

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
