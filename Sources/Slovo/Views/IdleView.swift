import SwiftUI
import TransCore

/// The drop zone and, under it, the settings that matter most as tiles, laid out like Control Center.
struct IdleView: View {
    @EnvironmentObject var transcriber: Transcriber
    var isTargeted: Bool

    var body: some View {
        VStack(spacing: Layout.spacing) {
            DropCard(isTargeted: isTargeted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ModelTile()
                LanguageTile()
                SwitchTile(symbol: "waveform.path.badge.minus", title: L("Пропуск тишины"), isOn: $transcriber.skipSilence,
                           help: L("Whisper не придумывает фразы там, где никто не говорит. Если пропадают тихие реплики, выключите"))
                SwitchTile(symbol: "scope", title: L("Точный режим"), isOn: $transcriber.beamSearch,
                           help: L("Whisper перебирает несколько вариантов каждой фразы: ошибок меньше, но распознавание медленнее"))
            }
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
                    .fill(isTargeted ? Brand.color : Brand.color.opacity(0.16))
                    .frame(width: 76, height: 76)
                PulsingSymbol(name: "waveform", active: isTargeted)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(isTargeted ? Color.white : Brand.color)
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
        .help(L("MP3, M4A, WAV, MP4, MOV, MKV и любые другие форматы. Распознавание идет на этом Mac, без интернета"))
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
