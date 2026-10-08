import SwiftUI
import TransCore

/// Progress of the running job; recognized phrases appear below as they come.
struct WorkingView: View {
    @EnvironmentObject var transcriber: Transcriber

    var body: some View {
        VStack(spacing: Layout.spacing) {
            VStack(spacing: 0) {
                if let url = transcriber.fileURL {
                    FileRow(url: url, subtitle: transcriber.media?.summary ?? L("Читаю файл…")) {
                        IconButton(symbol: "xmark", help: L("Отменить (Esc)")) { transcriber.cancel() }
                            .keyboardShortcut(.cancelAction)
                    }
                    RowDivider()
                }
                ProgressSection()
            }
            .card()

            ZStack {
                TranscriptTextView(text: .constant(transcriber.liveText), isEditable: false, followsEnd: true)
                if transcriber.liveText.isEmpty {
                    PulsingSymbol(name: "waveform", active: true)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Palette.tertiaryText)
                        .allowsHitTesting(false)
                }
            }
            .card()
            .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        }
    }
}

private struct ProgressSection: View {
    @EnvironmentObject var transcriber: Transcriber

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(transcriber.step.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let progress = transcriber.stepProgress {
                    percentText(progress)
                }
            }
            ProgressBar(value: transcriber.stepProgress)
            HStack(spacing: 8) {
                Text(transcriber.shortModelName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(remaining(at: context.date))
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.secondaryText)
        }
        .padding(12)
        .help(transcriber.step == .preparingGPU ? L("Один раз после установки или обновления") : "")
    }

    @ViewBuilder
    private func percentText(_ progress: Double) -> some View {
        let text = Text("\(Int(progress * 100))%")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
        if #available(macOS 14.0, *) {
            text.contentTransition(.numericText(value: progress))
                .animation(.snappy, value: Int(progress * 100))
        } else {
            text
        }
    }

    private func remaining(at now: Date) -> String {
        guard let remaining = transcriber.remainingTime(at: now) else { return "" }
        return L("Осталось примерно %@", formatDuration(max(1, remaining)))
    }
}
