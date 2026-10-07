import SwiftUI
import TransCore

/// Progress of the running job; recognized phrases appear below as they come.
struct WorkingView: View {
    @EnvironmentObject var transcriber: Transcriber

    var body: some View {
        VStack(spacing: 12) {
            if let url = transcriber.fileURL {
                FileHeader(url: url, subtitle: transcriber.media?.summary ?? L("Читаю файл…")) {
                    Button {
                        transcriber.cancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .glassCircleButton()
                    .help(L("Отменить (Esc)"))
                    .accessibilityLabel(L("Отменить"))
                }
            }
            ProgressCard()
            ZStack {
                PaperSurface()
                TranscriptTextView(text: .constant(transcriber.liveText), isEditable: false, followsEnd: true)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if transcriber.liveText.isEmpty {
                    VStack(spacing: 10) {
                        PulsingSymbol(name: "waveform", active: true)
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(.tertiary)
                        Text(L("Текст появится здесь по мере распознавания"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct ProgressCard: View {
    @EnvironmentObject var transcriber: Transcriber

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(transcriber.step.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                if let progress = transcriber.stepProgress {
                    percentText(progress)
                }
            }
            Group {
                if let progress = transcriber.stepProgress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(Color.accentColor)
            HStack(alignment: .center) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(detail(at: context.date))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(L("Отменить")) { transcriber.cancel() }
                    .glassButtonStyle()
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder
    private func percentText(_ progress: Double) -> some View {
        let text = Text("\(Int(progress * 100))%")
            .font(.rounded(24))
            .monospacedDigit()
        if #available(macOS 14.0, *) {
            text.contentTransition(.numericText(value: progress))
                .animation(.snappy, value: Int(progress * 100))
        } else {
            text
        }
    }

    private func detail(at now: Date) -> String {
        switch transcriber.step {
        case .opening: return L("Читаю сведения о файле")
        case .extracting: return L("Готовлю звук для распознавания")
        case .preparingGPU: return L("Один раз после установки или обновления")
        case .loadingModel: return transcriber.modelName
        case .recognizing:
            if let remaining = transcriber.remainingTime(at: now) {
                return L("Осталось примерно %@", formatDuration(max(1, remaining)))
            }
            return transcriber.modelName
        }
    }
}
