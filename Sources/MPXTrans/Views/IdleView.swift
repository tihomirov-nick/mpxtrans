import SwiftUI
import TransCore

/// Drop zone and the recognition settings that matter most (model and language).
struct IdleView: View {
    var isTargeted: Bool

    var body: some View {
        VStack(spacing: 12) {
            DropCard(isTargeted: isTargeted)
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ModelMenu()
                    LanguageMenu()
                    Spacer(minLength: 0)
                    SettingsButton()
                }
            }
        }
    }
}

private struct DropCard: View {
    @EnvironmentObject var transcriber: Transcriber
    var isTargeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(isTargeted ? 0.24 : 0.13))
                    .frame(width: 92, height: 92)
                PulsingSymbol(name: "waveform", active: isTargeted)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .scaleEffect(isTargeted ? 1.08 : 1)
            VStack(spacing: 6) {
                Text(isTargeted ? L("Отпустите файл") : L("Перетащите аудио или видео"))
                    .font(.system(size: 20, weight: .semibold))
                Text(L("MP3, M4A, WAV, MP4, MOV, MKV и любые другие форматы"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
            Button {
                transcriber.showOpenPanel()
            } label: {
                Label(L("Выбрать файл"), systemImage: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
            }
            .glassButtonStyle(prominent: true)
            .controlSize(.large)
            .help(L("Открыть файл (⌘O)"))
            Spacer(minLength: 0)
            Label(L("Работает без интернета, файлы не покидают Mac"), systemImage: "lock.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(in: RoundedRectangle(cornerRadius: 30, style: .continuous),
                      tint: isTargeted ? Color.accentColor.opacity(0.18) : nil)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(7)
                    .transition(.opacity)
            }
        }
        .scaleEffect(isTargeted ? 1.012 : 1)
    }
}
