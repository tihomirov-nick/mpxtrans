import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TransCore

/// Downloading and choosing Whisper models (the folder is shared with Subtits).
struct ModelManagerView: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Модели распознавания"))
                            .font(.system(size: 22, weight: .bold))
                        Text(L("Модель скачивается один раз и хранится на этом Mac, распознавание работает без интернета. Папка моделей общая с Subtits: скачанное в одном приложении доступно в другом."))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 6)

                    ForEach(ModelCatalog.models) { info in
                        ModelRow(info: info)
                    }
                    if !modelStore.customModels.isEmpty {
                        Text(L("Свои модели"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        ForEach(modelStore.customModels, id: \.self) { url in
                            CustomModelRow(url: url)
                        }
                    }
                }
                .padding(20)
            }

            HStack(spacing: 8) {
                Button {
                    addCustomModel()
                } label: {
                    Label(L("Своя модель (.bin)…"), systemImage: "plus")
                }
                .glassButtonStyle()
                .help(L("Любая модель Whisper в формате ggml для whisper.cpp"))
                Button {
                    NSWorkspace.shared.open(AppPaths.modelsDir)
                } label: {
                    Label(L("Папка моделей"), systemImage: "folder")
                }
                .glassButtonStyle()
                Spacer(minLength: 8)
                if let error = modelStore.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .frame(maxWidth: 260, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 520, minHeight: 480)
        .background(Backdrop())
        .onAppear { modelStore.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            modelStore.refresh()
        }
    }

    private func addCustomModel() {
        let panel = NSOpenPanel()
        panel.title = L("Выберите модель Whisper (ggml .bin)")
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        modelStore.importModel(from: url)
    }
}

private struct Badge: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct ModelRow: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    let info: WhisperModelInfo

    var body: some View {
        let installed = modelStore.installed.contains(info.id)
        let download = modelStore.downloads[info.id]
        let selected = transcriber.modelID == info.id && installed
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(info.name)
                        .font(.system(size: 13, weight: .semibold))
                    if info.recommended { Badge(text: L("Рекомендуется")) }
                    if info.russianTuned { Badge(text: L("Русский"), color: .purple) }
                    if selected { Badge(text: L("Выбрана"), color: .green) }
                }
                Text(info.details)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(info.sizeText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            if let download {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: download.fraction)
                        .frame(width: 140)
                    Text(progressText(download))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(download.retryMessage == nil ? Color.secondary : Color.orange)
                        .frame(maxWidth: 220, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
                if !download.verifying {
                    Button {
                        modelStore.cancelDownload(info.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .glassCircleButton()
                    .controlSize(.small)
                    .help(L("Отменить загрузку"))
                }
            } else if installed {
                if !selected {
                    Button(L("Выбрать")) { transcriber.modelID = info.id }
                        .glassButtonStyle()
                        .controlSize(.small)
                }
                Button {
                    modelStore.delete(info)
                    transcriber.ensureValidModelSelection()
                } label: {
                    Image(systemName: "trash")
                }
                .glassCircleButton()
                .controlSize(.small)
                .help(L("Удалить модель с диска (и из Subtits тоже)"))
            } else {
                Button {
                    modelStore.download(info)
                } label: {
                    Label(L("Скачать"), systemImage: "arrow.down")
                }
                .glassButtonStyle(prominent: info.recommended)
                .controlSize(.small)
            }
        }
        .padding(14)
        .glassSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1.5)
        )
    }

    private func progressText(_ state: ModelStore.DownloadState) -> String {
        if state.verifying { return L("Проверка файла…") }
        if let retry = state.retryMessage { return retry }
        var text = L("%@ из %@", formatBytes(state.received), formatBytes(state.total))
        if state.bytesPerSecond > 0 {
            text += " · " + formatBytes(Int64(state.bytesPerSecond)) + L("/с")
        }
        return text
    }
}

private struct CustomModelRow: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    let url: URL

    var body: some View {
        let id = "custom:" + url.lastPathComponent
        let selected = transcriber.modelID == id
        HStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if selected { Badge(text: L("Выбрана"), color: .green) }
            Spacer()
            if !selected {
                Button(L("Выбрать")) { transcriber.modelID = id }
                    .glassButtonStyle()
                    .controlSize(.small)
            }
            Button {
                modelStore.deleteCustom(url)
                transcriber.ensureValidModelSelection()
            } label: {
                Image(systemName: "trash")
            }
            .glassCircleButton()
            .controlSize(.small)
            .help(L("Удалить модель с диска"))
        }
        .padding(14)
        .glassSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
