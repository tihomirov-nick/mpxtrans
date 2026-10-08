import SwiftUI
import AppKit
import TransCore

// Updates in the window and in Settings. The work is done by Updater (shared by the author's apps); the words are
// Slovo's own.

/// A new version offered over the drop zone: what is new and what to do, then the download, then a problem if any.
/// It is shown on the drop zone only, so Slovo never restarts in the middle of a transcription or over a transcript
/// that is not saved yet.
struct UpdateCard: View {
    @EnvironmentObject var updater: Updater

    var body: some View {
        switch updater.state {
        case .available(let release):
            card(symbol: "arrow.down", tint: Brand.color, title: L("Доступна версия %@", release.version),
                 detail: updater.isDevelopmentBuild ? L("Сборка для разработки не обновляется")
                                                    : releaseSummary(release.notes, fallback: release.title),
                 detailHelp: releaseHelp(release.notes)) {
                Button(L("Пропустить")) { updater.skip() }
                    .appButton(.link)
                    .controlSize(.small)
                    .help(L("Больше не предлагать эту версию"))
                Spacer(minLength: 8)
                Button(L("Позже")) { updater.dismiss() }
                    .appButton(.secondary)
                    .controlSize(.small)
                    .help(L("Напомнить при следующей проверке"))
                if updater.isDevelopmentBuild {
                    releasePageButton
                } else {
                    Button(L("Обновить")) { updater.install() }
                        .appButton(.primary)
                        .controlSize(.small)
                        .help(updater.canInstallInPlace ? L("Скачать, установить и перезапустить Slovo")
                                                        : L("Скачать DMG и открыть его в Finder. Заменить приложение в этой папке нельзя"))
                }
            }
        case .downloading(let release, let progress):
            card(symbol: "arrow.down", tint: Brand.color, title: L("Загружаю версию %@", release.version),
                 trailing: "\(Int(progress * 100))%", progress: progress) {
                Spacer(minLength: 8)
                Button(L("Отменить")) { updater.cancel() }
                    .appButton(.secondary)
                    .controlSize(.small)
            }
        case .installing(let release):
            // Files are not taken meanwhile (Transcriber.isUpdating).
            card(symbol: "arrow.down", tint: Brand.color, title: L("Устанавливаю обновление…"),
                 detail: L("Версия %@, после установки перезапущусь", release.version), progress: .some(nil)) { EmptyView() }
        case .failed(.cannotReplace, .some(let release)) where !updater.isDevelopmentBuild:
            // Downloaded, but this copy cannot be replaced (not in a writable folder): the DMG opens in Finder.
            card(symbol: "arrow.down", tint: Brand.color, title: L("Версия %@ скачана", release.version),
                 detail: L("Перетащите Slovo из DMG в папку «Программы», и дальше обновления будут ставиться автоматически")) {
                Spacer(minLength: 8)
                Button(L("Позже")) { updater.dismiss() }
                    .appButton(.secondary)
                    .controlSize(.small)
                Button(L("Открыть DMG")) { updater.openReleasePage() }
                    .appButton(.primary)
                    .controlSize(.small)
                    .help(L("Показать скачанный DMG в Finder"))
            }
        case .failed(let failure, .some(let release)):
            card(symbol: "exclamationmark", tint: .orange, title: L("Не удалось обновить до версии %@", release.version),
                 detail: updateFailureText(failure)) {
                Spacer(minLength: 8)
                Button(L("Позже")) { updater.dismiss() }
                    .appButton(.secondary)
                    .controlSize(.small)
                releasePageButton
            }
        default:
            EmptyView()
        }
    }

    private var releasePageButton: some View {
        Button(L("Страница релиза")) { updater.openReleasePage() }
            .appButton(.primary)
            .controlSize(.small)
            .help(L("Открыть релиз на GitHub, там можно скачать DMG"))
    }

    /// `progress`: nil for no bar, .some(nil) for a bar without a value.
    private func card<Buttons: View>(symbol: String, tint: Color, title: String, trailing: String? = nil,
                                     detail: String? = nil, detailHelp: String? = nil, progress: Double?? = nil,
                                     @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tint == Brand.color ? Brand.ink : .white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let trailing {
                            Text(trailing)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(1)
                            .help(detailHelp ?? detail)
                    }
                }
            }
            if let progress {
                ProgressBar(value: progress)
            }
            HStack(spacing: 8) { buttons() }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Settings rows: automatic checks, then the version, what the last check found and a check now.
struct UpdateSettingRows: View {
    @EnvironmentObject var updater: Updater

    var body: some View {
        SettingRow(title: L("Проверять обновления"),
                   help: L("Раз в день Slovo смотрит, нет ли нового релиза на GitHub, и предлагает обновиться")) {
            Switch(isOn: $updater.automaticChecks)
        }
        HStack(spacing: 8) {
            Text(([L("Версия %@", updater.currentVersion)] + [status].compactMap { $0 }).joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(statusHelp)
            Spacer(minLength: 6)
            Button(L("Проверить сейчас")) { updater.check(userInitiated: true) }
                .appButton(.secondary)
                .controlSize(.small)
                .disabled(updater.isBusy)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var status: String? {
        switch updater.state {
        case .idle: return updater.isDevelopmentBuild ? L("Сборка для разработки") : nil
        case .checking: return L("Проверяю…")
        case .upToDate: return L("Обновлений нет")
        case .available(let release): return L("Доступна %@", release.version)
        case .downloading(let release, _): return L("Загружаю %@", release.version)
        case .installing(let release): return L("Устанавливаю %@", release.version)
        case .failed(let failure, nil): return updateFailureText(failure, short: true)
        case .failed(_, .some): return L("Не удалось обновить")
        }
    }

    private var statusHelp: String {
        switch updater.state {
        case .failed(let failure, _): return updateFailureText(failure)
        default:
            return updater.isDevelopmentBuild
                ? L("Slovo запущен из папки сборки, такая копия не проверяет и не ставит обновления")
                : L("Обновления приходят из релизов Slovo на GitHub")
        }
    }

}

extension Updater {
    /// Checking, downloading or installing: another check waits.
    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }
}

/// What went wrong, in a line; `short` fits next to the version in Settings.
func updateFailureText(_ failure: Updater.Failure, short: Bool = false) -> String {
    switch failure {
    case .offline: return L("Нет связи с GitHub")
    case .rateLimited: return short ? L("Проверки ограничены") : L("GitHub временно ограничил проверки, попробуйте позже")
    case .noInstaller: return short ? L("Нет DMG") : L("В релизе нет DMG")
    case .download: return L("Загрузка прервалась")
    case .damaged: return L("DMG повреждён")
    case .notTrusted: return short ? L("Чужая подпись") : L("Подпись обновления не совпадает с подписью Slovo")
    case .cannotReplace: return L("Не удалось заменить приложение")
    }
}

/// The first sentence or point of the release notes (Markdown), as plain text for one line.
func releaseSummary(_ notes: String, fallback: String) -> String {
    let lines = notes.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    let line = lines.first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
    let plain = markdownless(line)
    return plain.isEmpty ? fallback : plain
}

/// The notes without Markdown, shortened for a tooltip.
func releaseHelp(_ notes: String) -> String {
    let text = notes.split(whereSeparator: \.isNewline).map { markdownless(String($0)) }.filter { !$0.isEmpty }.joined(separator: "\n")
    return text.count > 600 ? String(text.prefix(600)) + "…" : text
}

private func markdownless(_ line: String) -> String {
    var text = line.trimmingCharacters(in: .whitespaces)
    while let first = text.first, "#-*+>".contains(first) { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
    for mark in ["**", "__", "`"] { text = text.replacingOccurrences(of: mark, with: "") }
    // [text](link) → text
    while let open = text.range(of: "]("), let close = text.range(of: ")", range: open.upperBound..<text.endIndex),
          let start = text.range(of: "[", options: .backwards, range: text.startIndex..<open.lowerBound) {
        text.replaceSubrange(start.lowerBound..<close.upperBound, with: text[start.upperBound..<open.lowerBound])
    }
    return text
}
