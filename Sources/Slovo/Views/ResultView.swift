import SwiftUI
import TransCore

/// The transcript: the file (or another pass over it), the format, editable text and the actions.
struct ResultView: View {
    @EnvironmentObject var transcriber: Transcriber
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var debug = DebugHooks.State.shared
    @State private var showRerun = false

    var body: some View {
        VStack(spacing: Layout.spacing) {
            ZStack(alignment: .top) {
                if showRerun || debug.rerunPanel {
                    RerunPanel(isPresented: $showRerun)
                        .transition(.blurAppear(reduceMotion: reduceMotion))
                } else if let url = transcriber.fileURL {
                    FileRow(url: url, subtitle: subtitle) {
                        IconButton(symbol: "arrow.clockwise", help: L("Распознать заново, например другой моделью")) {
                            showRerun = true
                        }
                        IconButton(symbol: "xmark", help: L("Закрыть и распознать другой файл")) { transcriber.reset() }
                    }
                    .transition(.blurAppear(reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: .infinity)
            .card()
            .animation(Motion.animation(Motion.spring, reduceMotion: reduceMotion), value: showRerun)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    // What the result is, and its case and punctuation (as in Subline's style).
                    VStack(alignment: .leading, spacing: 6) {
                        Segments(selection: $transcriber.format, options: TranscriptFormat.allCases.map { ($0, $0.title) })
                        Segments(selection: $transcriber.caseMode, options: TextCaseMode.allCases.map { ($0, $0.shortTitle) },
                                 help: \.title)
                    }
                    Spacer(minLength: 8)
                    Text(transcriber.wordCountText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                        .frame(height: 28)
                        .help(L("Готово за %@", formatDuration(transcriber.elapsed)))
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
                RowDivider(leading: 0)
                TranscriptTextView(text: Binding(
                    get: { transcriber.shownText(transcriber.format) },
                    set: { transcriber.editShownText($0) }
                ), isEditable: true, followsEnd: false, document: transcriber.format)
            }
            .card()
            .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))

            ActionBar()
        }
    }

    private var subtitle: String {
        guard let transcript = transcriber.transcript else { return "" }
        let model = transcriber.modelStore.shortName(of: transcript.modelName)
        return [formatDuration(transcript.duration), model, transcriber.languageText].joined(separator: " · ")
    }
}

private struct ActionBar: View {
    @EnvironmentObject var transcriber: Transcriber
    @State private var copied = false
    @State private var saved = false

    var body: some View {
        HStack(spacing: 8) {
            ShareButton(text: { transcriber.currentText }, subject: transcriber.baseName)
            if transcriber.isEdited {
                Button {
                    transcriber.revertEdits()
                } label: {
                    Label(L("Вернуть"), systemImage: "arrow.uturn.backward")
                }
                .appButton(.link)
                .help(L("Вернуть исходный текст, правки в этом виде пропадут"))
                .transition(.opacity)
            }
            Spacer(minLength: 8)
            Button {
                transcriber.save { success in
                    if success { flash($saved) }
                }
            } label: {
                StableLabel(text: saved ? L("Сохранено") : L("Сохранить"), variants: [L("Сохранено"), L("Сохранить")])
            }
            .appButton(.secondary)
            .help(L("Сохранить в файл (⌘S)"))
            Button {
                transcriber.copyText()
                flash($copied)
            } label: {
                StableLabel(text: copied ? L("Скопировано") : L("Скопировать"), variants: [L("Скопировано"), L("Скопировать")])
            }
            .appButton(.primary)
            .help(L("Скопировать весь текст (⇧⌘C)"))
        }
        .animation(Motion.quick, value: transcriber.isEdited)
    }

    private func flash(_ flag: Binding<Bool>) {
        withAnimation(Motion.quick) { flag.wrappedValue = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(Motion.quick) { flag.wrappedValue = false }
        }
    }
}

/// Model and language for another pass over the same file, in place of the file's row.
private struct RerunPanel: View {
    @EnvironmentObject var transcriber: Transcriber
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            SettingRow(title: L("Модель")) { ModelCapsule() }
            SettingRow(title: L("Язык")) { LanguageCapsule() }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L("Отмена")) { close() }
                    .appButton(.secondary)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button(L("Распознать")) {
                    close()
                    transcriber.retranscribe()
                }
                .appButton(.primary)
                .controlSize(.small)
                .help(L("Распознать файл заново, правки текста пропадут"))
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
        }
    }

    private func close() {
        isPresented = false
        DebugHooks.State.shared.rerunPanel = false
    }
}
