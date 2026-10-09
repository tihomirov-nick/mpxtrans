import SwiftUI
import AppKit
import TransCore

// Updates in the window and in Settings. The work is done by Updater (shared by the author's apps); the words are
// Slovo's own.

/// A new version offered above the window's content: what is new and what to do, then the download, then a problem if
/// any, and the restart. ContentView hides it while a transcription runs; over a transcript that only the window holds
/// and during a model download "Update" waits, so that the restart loses nothing.
struct UpdateCard: View {
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var transcriber: Transcriber
    @EnvironmentObject var modelStore: ModelStore

    var body: some View {
        switch updater.state {
        case .available(let release):
            // An installer that only opens in Finder restarts nothing.
            let hold = updater.installsByItself ? installHold : nil
            card(symbol: "arrow.down", tint: Brand.color, title: L("Доступна версия %@", release.version),
                 detail: updater.isDevelopmentBuild ? L("Сборка для разработки не обновляется")
                                                    : hold ?? releaseSummary(release.notes, fallback: release.title),
                 detailHelp: hold ?? releaseHelp(release.notes)) {
                Button(L("Пропустить")) { updater.skip() }
                    .appButton(.link)
                    .controlSize(.small)
                    .help(L("Больше не предлагать эту версию"))
                Spacer(minLength: 8)
                Button(L("Позже")) { updater.dismiss() }
                    .appButton(.secondary)
                    .controlSize(.small)
                    .help(L("Напомнить через сутки"))
                if updater.isDevelopmentBuild {
                    releasePageButton
                } else {
                    Button(L("Обновить")) { updater.install() }
                        .appButton(.primary)
                        .controlSize(.small)
                        .disabled(hold != nil)
                        .help(updater.installsByItself ? L("Скачать, установить и перезапустить Slovo")
                                                       : L("Скачать установщик и открыть его в Finder. Новую версию нужно будет поставить вручную"))
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
            // Files are not taken meanwhile (Transcriber.isUpdating). An update that installed itself shows this for a
            // moment before the restart (AppDelegate.applicationShouldTerminate).
            card(symbol: "arrow.down", tint: Brand.color, title: L("Обновляюсь до версии %@…", release.version),
                 detail: L("Сейчас перезапущусь"), progress: .some(nil)) { EmptyView() }
        case .failed(.cannotReplace, .some(let release)) where !updater.isDevelopmentBuild:
            // Downloaded, but it could go neither over this copy nor into an Applications folder: the installer opens
            // in Finder.
            card(symbol: "arrow.down", tint: Brand.color, title: L("Версия %@ скачана", release.version),
                 detail: L("Не получилось поставить новую версию. Откройте установщик и перетащите Slovo в папку «Программы»")) {
                Spacer(minLength: 8)
                Button(L("Позже")) { updater.dismiss() }
                    .appButton(.secondary)
                    .controlSize(.small)
                Button(L("Открыть установщик")) { updater.openReleasePage() }
                    .appButton(.primary)
                    .controlSize(.small)
                    .help(L("Показать скачанный установщик в Finder"))
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

    /// Why "Update" waits: the restart would lose the transcript or the model being downloaded.
    private var installHold: String? {
        if transcriber.hasUnsavedResult { return L("Сначала сохраните или скопируйте текст") }
        if !modelStore.downloads.isEmpty { return L("Сначала дождитесь, пока скачается модель") }
        return nil
    }

    private var releasePageButton: some View {
        Button(L("Скачать вручную")) { updater.openReleasePage() }
            .appButton(.primary)
            .controlSize(.small)
            .help(L("Открыть страницу новой версии в браузере, там можно скачать установщик"))
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

/// The settings row for opening at login (Updater.LoginItem), and when System Settings has switched it off, the way there.
struct LoginItemRows: View {
    @ObservedObject private var loginItem = Updater.LoginItem.shared
    @State private var needsApproval = false

    var body: some View {
        SettingRow(title: L("Запускать при входе"),
                   help: L("При входе в систему Slovo запускается без окна и значка в Dock, чтобы вовремя ставить обновления. Окно появится, когда вы откроете Slovo")) {
            Switch(isOn: Binding(get: { loginItem.isEnabled }, set: {
                loginItem.set($0)
                needsApproval = loginItem.needsApproval
            }))
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        if needsApproval {
            HStack(spacing: 8) {
                Text(L("Выключено в macOS"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(L("Запуск при входе выключен в Системных настройках, в разделе «Объекты входа». Включить его можно только там"))
                Spacer(minLength: 6)
                Button(L("Открыть «Объекты входа»")) { loginItem.openSystemSettings() }
                    .appButton(.secondary)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .overlay(alignment: .bottom) { RowDivider() }
        }
    }

    /// Read again when Settings open and when the user comes back to Slovo: System Settings may have changed it.
    private func refresh() {
        loginItem.refresh()
        needsApproval = loginItem.needsApproval
    }
}

/// Settings rows: automatic checks and installs, then the version, what the last check found and a check now.
struct UpdateSettingRows: View {
    @EnvironmentObject var updater: Updater

    var body: some View {
        SettingRow(title: L("Проверять обновления"),
                   help: L("Slovo смотрит, нет ли новой версии, сразу после запуска и потом каждые три часа")) {
            Switch(isOn: $updater.automaticChecks)
        }
        SettingRow(title: L("Обновлять автоматически"),
                   help: L("Новая версия скачивается и ставится сама, когда Slovo ничем не занят. Пока идёт расшифровка или готовый текст ещё не сохранён и не скопирован, обновление ждёт. Если выключить, Slovo будет только предлагать обновиться")) {
            Switch(isOn: $updater.automaticInstall)
        }
        .disabled(!updater.automaticChecks)
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
        case .idle:
            // An update that installs itself is under way.
            if let job = updater.automaticUpdate {
                return job.ready ? L("%@ скачана", job.release.version) : L("Загружаю %@", job.release.version)
            }
            return updater.isDevelopmentBuild ? L("Сборка для разработки") : nil
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
        case .idle where updater.automaticUpdate?.ready == true:
            return L("Новая версия встанет, когда Slovo освободится или закроется")
        default:
            return updater.isDevelopmentBuild
                ? L("Slovo запущен из папки сборки, такая копия не проверяет и не ставит обновления")
                : L("Новую версию Slovo ставит сам и перезапускается")
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
    case .offline: return short ? L("Нет связи") : L("Нет связи с сервером обновлений")
    case .rateLimited: return short ? L("Проверки ограничены") : L("Сервер обновлений временно ограничил проверки, попробуйте позже")
    case .noInstaller: return short ? L("Нет установщика") : L("У новой версии нет установщика")
    case .download: return L("Загрузка прервалась")
    case .damaged: return L("Установщик повреждён")
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
