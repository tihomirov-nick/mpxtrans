import SwiftUI
import AppKit
import TransCore

/// Settings (⌘,): recognition options that are changed rarely.
struct SettingsView: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                ModelPicker(title: L("Модель"))
                LanguagePicker(title: L("Язык речи"))
                HStack {
                    Spacer()
                    Button(L("Управление моделями…")) { openWindow(id: "models") }
                }
            } header: {
                Text(L("Распознавание"))
            }

            Section {
                Toggle(isOn: $transcriber.skipSilence) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Пропускать тишину и музыку"))
                        Text(L("Whisper не будет придумывать фразы там, где никто не говорит. Если пропадают тихие реплики, выключите."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $transcriber.beamSearch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Точный режим"))
                        Text(L("Перебирает несколько вариантов фразы: меньше ошибок, но медленнее."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L("Качество"))
            }

            Section {
                TextField(L("Подсказка"), text: $transcriber.prompt, prompt: Text(L("Например: Сбербанк, Kubernetes, Анна Ковальчук")), axis: .vertical)
                    .lineLimit(2...4)
                    .labelsHidden()
            } header: {
                Text(L("Имена и термины"))
            } footer: {
                Text(L("Слова, которые встречаются в записях: Whisper будет писать их правильно."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { modelStore.refresh() }
    }
}
