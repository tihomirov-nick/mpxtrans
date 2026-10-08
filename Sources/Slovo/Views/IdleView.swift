import SwiftUI
import TransCore

/// The drop zone and, under it, the settings that matter most as tiles, laid out like Control Center; a new version
/// of Slovo is offered above.
struct IdleView: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var updater: Updater
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isTargeted: Bool

    var body: some View {
        VStack(spacing: Layout.spacing) {
            if offersUpdate {
                UpdateCard()
                    .transition(.blurAppear(reduceMotion: reduceMotion))
            }
            DropCard(isTargeted: isTargeted)
                // Off for the second or two an update takes to install.
                .disabled(transcriber.isUpdating)
                .opacity(transcriber.isUpdating ? 0.5 : 1)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ModelTile()
                LanguageTile()
                SwitchTile(symbol: "waveform.path.badge.minus", title: L("Пропуск тишины"), isOn: $transcriber.skipSilence,
                           help: L("Whisper не придумывает фразы там, где никто не говорит. Если пропадают тихие реплики, выключите пропуск тишины"))
                SwitchTile(symbol: "scope", title: L("Точный режим"), isOn: $transcriber.beamSearch,
                           help: L("Whisper перебирает несколько вариантов каждой фразы: ошибок меньше, но распознавание медленнее"))
            }
        }
        .animation(Motion.animation(Motion.spring, reduceMotion: reduceMotion), value: offersUpdate)
    }

    private var offersUpdate: Bool {
        switch updater.state {
        case .available, .downloading, .installing, .failed(_, .some): return true
        default: return false
        }
    }
}

private struct DropCard: View {
    @EnvironmentObject var transcriber: Transcriber
    var isTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isTargeted ? Brand.color : Color.white.opacity(0.12))
                    .frame(width: 76, height: 76)
                PulsingSymbol(name: "waveform", size: 32, weight: .semibold, color: isTargeted ? Brand.ink : Brand.color,
                              active: isTargeted)
            }
            .scaleEffect(isTargeted ? 1.08 : 1)
            Text(isTargeted ? L("Отпустите файл") : L("Перетащите аудио или видео"))
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button(L("Выбрать файл")) {
                transcriber.showOpenPanel()
            }
            .appButton(.primary)
            .controlSize(.large)
            .help(L("Открыть файл (⌘O)"))
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card(radius: 20)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Brand.color, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .transition(.opacity)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .help(L("MP3, M4A, WAV, MP4, MOV, MKV и любые другие форматы. Распознавание идёт на этом Mac, без интернета"))
        .overlay(alignment: .topTrailing) {
            SettingsButton()
                .padding(8)
        }
    }
}

/// Round button that opens Settings.
struct SettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        IconButton(symbol: "gearshape", help: L("Настройки")) { openWindow(id: "settings") }
    }
}
