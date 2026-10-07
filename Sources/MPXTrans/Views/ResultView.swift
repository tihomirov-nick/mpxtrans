import SwiftUI
import TransCore

/// The transcript: format switch, editable text and the actions (copy, save, share).
struct ResultView: View {
    @EnvironmentObject var transcriber: Transcriber
    @State private var showRerun = false

    var body: some View {
        VStack(spacing: 10) {
            if let url = transcriber.fileURL {
                FileHeader(url: url, subtitle: subtitle) {
                    Button {
                        showRerun.toggle()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .glassCircleButton()
                    .help(L("Распознать заново, например другой моделью"))
                    .accessibilityLabel(L("Распознать заново"))
                    .popover(isPresented: $showRerun, arrowEdge: .bottom) {
                        RerunPopover(isPresented: $showRerun)
                            .environmentObject(transcriber)
                            .environmentObject(transcriber.modelStore)
                    }
                    Button {
                        transcriber.reset()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .glassCircleButton()
                    .help(L("Закрыть и распознать другой файл"))
                    .accessibilityLabel(L("Закрыть"))
                }
            }

            Picker("", selection: $transcriber.format) {
                ForEach(TranscriptFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)

            ZStack {
                PaperSurface()
                TranscriptTextView(text: Binding(
                    get: { transcriber.texts[transcriber.format] ?? "" },
                    set: { transcriber.texts[transcriber.format] = $0 }
                ), isEditable: true, followsEnd: false)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            ActionBar()
        }
    }

    private var subtitle: String {
        guard let transcript = transcriber.transcript else { return "" }
        return [formatDuration(transcript.duration), transcript.modelName, transcriber.languageText].joined(separator: " · ")
    }
}

private struct ActionBar: View {
    @EnvironmentObject var transcriber: Transcriber
    @State private var copied = false
    @State private var saved = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transcriber.wordCountText)
                    .font(.system(size: 12, weight: .semibold))
                if transcriber.isEdited {
                    Button {
                        transcriber.revertEdits()
                    } label: {
                        Label(L("Вернуть"), systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help(L("Вернуть исходный текст: ваши правки в этом формате пропадут"))
                } else {
                    Text(L("готово за %@", formatDuration(transcriber.elapsed)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .padding(.leading, 6)
            Spacer(minLength: 6)
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        transcriber.copyText()
                        flash($copied)
                    } label: {
                        Label(copied ? L("Скопировано") : L("Скопировать"), systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .glassButtonStyle(prominent: true)
                    .controlSize(.large)
                    .help(L("Скопировать весь текст (⇧⌘C)"))

                    Button {
                        transcriber.save { success in
                            if success { flash($saved) }
                        }
                    } label: {
                        Label(saved ? L("Сохранено") : L("Сохранить"), systemImage: saved ? "checkmark" : "arrow.down.doc")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .glassButtonStyle()
                    .controlSize(.large)
                    .help(L("Сохранить в файл (⌘S)"))

                    ShareButton(text: { transcriber.currentText }, subject: transcriber.baseName)
                        .glassCircleButton()
                        .controlSize(.large)
                }
                .fixedSize()
            }
            .layoutPriority(1)
        }
    }

    private func flash(_ flag: Binding<Bool>) {
        withAnimation(Motion.quick) { flag.wrappedValue = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(Motion.quick) { flag.wrappedValue = false }
        }
    }
}

/// Model and language for another pass over the same file.
private struct RerunPopover: View {
    @EnvironmentObject var transcriber: Transcriber
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Распознать заново"))
                    .font(.system(size: 15, weight: .semibold))
                Text(L("Выберите другую модель или язык. Правки текста при этом пропадут."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                ModelPicker()
                LanguagePicker()
            }
            HStack {
                Spacer()
                Button(L("Отмена")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(L("Распознать")) {
                    isPresented = false
                    transcriber.retranscribe()
                }
                .glassButtonStyle(prominent: true)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 320)
    }
}
