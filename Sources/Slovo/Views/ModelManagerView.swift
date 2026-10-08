import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TransCore

/// Downloading and choosing Whisper models (the folder is shared with Subline).
struct ModelManagerView: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.spacing) {
                VStack(spacing: 0) {
                    ForEach(ModelCatalog.models) { info in
                        ModelRow(info: info, last: info.id == ModelCatalog.models.last?.id)
                    }
                }
                .card()
                if !modelStore.customModels.isEmpty {
                    Text(L("Свои модели"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                        .padding(.leading, 12)
                        .padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(modelStore.customModels, id: \.self) { url in
                            CustomModelRow(url: url, last: url == modelStore.customModels.last)
                        }
                    }
                    .card()
                }
                HStack(spacing: 8) {
                    Button(L("Своя модель (.bin)…")) { addCustomModel() }
                        .appButton(.secondary)
                        .controlSize(.small)
                        .help(L("Любая модель Whisper в формате ggml для whisper.cpp"))
                    Button(L("Папка моделей")) { NSWorkspace.shared.open(AppPaths.modelsDir) }
                        .appButton(.secondary)
                        .controlSize(.small)
                        .help(L("Папка общая с Subline: модель, скачанная в одном приложении, есть и в другом"))
                    Spacer(minLength: 8)
                    if let error = modelStore.lastError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(error)
                    }
                }
            }
            .padding([.horizontal, .bottom], Layout.padding)
        }
        .frame(minWidth: 500, minHeight: 300)
        .blackWindow(title: L("Модели распознавания"))
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
    var color: Color = Brand.color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.18), in: Capsule())
    }
}

/// One model of the catalog on one line; pointing at it tells what the model is good for.
private struct ModelRow: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    let info: WhisperModelInfo
    let last: Bool

    var body: some View {
        let installed = modelStore.installed.contains(info.id)
        let download = modelStore.downloads[info.id]
        let selected = transcriber.modelID == info.id && installed
        HStack(spacing: 8) {
            Text(info.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if info.recommended { Badge(text: L("Рекомендуется")) }
            if info.russianTuned { Badge(text: L("Русский"), color: Color(red: 0.75, green: 0.45, blue: 1)) }
            Spacer(minLength: 8)
            if let download {
                Text(progressText(download))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(download.retryMessage == nil ? Palette.secondaryText : Color.orange)
                    .lineLimit(1)
                    .fixedSize()
                    .help(progressHelp(download))
                ProgressBar(value: download.verifying ? nil : download.fraction)
                    .frame(width: 90)
                if !download.verifying {
                    IconButton(symbol: "xmark", help: L("Отменить загрузку"), size: 24) { modelStore.cancelDownload(info.id) }
                }
            } else if installed {
                Text(info.sizeText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
                    .fixedSize()
                if selected {
                    SelectedMark()
                } else {
                    Button(L("Выбрать")) { transcriber.modelID = info.id }
                        .appButton(.link)
                        .controlSize(.small)
                }
                IconButton(symbol: "trash", help: L("Удалить модель с диска (и из Subline тоже)"), size: 24) {
                    modelStore.delete(info)
                    transcriber.ensureValidModelSelection()
                }
            } else {
                Text(info.sizeText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
                    .fixedSize()
                Button(L("Скачать")) { modelStore.download(info) }
                    .appButton(info.recommended ? .primary : .secondary)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .contentShape(Rectangle())
        .help(info.details)
        .overlay(alignment: .bottom) {
            if !last { RowDivider() }
        }
        .animation(Motion.quick, value: download != nil)
    }

    private func progressText(_ state: ModelStore.DownloadState) -> String {
        if state.verifying { return L("Проверка файла…") }
        if state.retryMessage != nil { return L("Повтор…") }
        return "\(Int(state.fraction * 100))%"
    }

    private func progressHelp(_ state: ModelStore.DownloadState) -> String {
        if let retry = state.retryMessage { return retry }
        var text = L("%@ из %@", formatBytes(state.received), formatBytes(state.total))
        if state.bytesPerSecond > 0 {
            text += " · " + formatBytes(Int64(state.bytesPerSecond)) + L("/с")
        }
        return text
    }
}

/// The chosen model: a checkmark in the brand color.
private struct SelectedMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Brand.color)
            .help(L("Выбрана"))
            .accessibilityLabel(L("Выбрана"))
    }
}

private struct CustomModelRow: View {
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore
    let url: URL
    let last: Bool

    var body: some View {
        let id = "custom:" + url.lastPathComponent
        let selected = transcriber.modelID == id
        HStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Text(url.lastPathComponent)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if selected {
                SelectedMark()
            } else {
                Button(L("Выбрать")) { transcriber.modelID = id }
                    .appButton(.link)
                    .controlSize(.small)
            }
            IconButton(symbol: "trash", help: L("Удалить модель с диска"), size: 24) {
                modelStore.deleteCustom(url)
                transcriber.ensureValidModelSelection()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            if !last { RowDivider() }
        }
    }
}
