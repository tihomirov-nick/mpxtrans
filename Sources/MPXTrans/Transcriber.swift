import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TransCore

/// Thread-safe cancellation flag for code that cannot use Task cancellation (whisper callbacks).
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// Runs on the main actor in the order of calls (whisper reports from a background thread).
func onMain(_ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
}

/// The window's state: settings, the running job and its result.
@MainActor
final class Transcriber: ObservableObject {
    enum Phase: Equatable {
        case idle, working, done
    }

    enum Step: Equatable {
        case opening, extracting, preparingGPU, loadingModel, recognizing

        var title: String {
            switch self {
            case .opening: return L("Открываю файл")
            case .extracting: return L("Извлекаю звук")
            case .preparingGPU: return L("Готовлю видеокарту")
            case .loadingModel: return L("Загружаю модель")
            case .recognizing: return L("Распознаю речь")
            }
        }
    }

    let modelStore = ModelStore()
    private let defaults = UserDefaults.standard

    // MARK: Settings

    @Published var modelID: String { didSet { defaults.set(modelID, forKey: "modelID") } }
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var prompt: String { didSet { defaults.set(prompt, forKey: "prompt") } }
    @Published var skipSilence: Bool { didSet { defaults.set(skipSilence, forKey: "skipSilence") } }
    @Published var beamSearch: Bool { didSet { defaults.set(beamSearch, forKey: "beamSearch") } }
    @Published var format: TranscriptFormat {
        didSet {
            defaults.set(format.rawValue, forKey: "format")
            if phase == .working { liveText = format.render(segments) }
        }
    }

    // MARK: Job

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var fileURL: URL?
    @Published private(set) var media: MediaInfo?
    @Published private(set) var step: Step = .opening
    /// Progress of the current step (extracting or recognizing), nil while it cannot be measured.
    @Published private(set) var stepProgress: Double?
    @Published private(set) var recognitionStartedAt: Date?
    /// Text recognized so far, in the chosen format.
    @Published private(set) var liveText = ""
    @Published private(set) var transcript: Transcript?
    /// Time from dropping the file to the result.
    @Published private(set) var elapsed: TimeInterval = 0
    /// Text of each format as shown; the user may edit it.
    @Published var texts: [TranscriptFormat: String] = [:]
    @Published var errorMessage: String?
    /// The models window should open (a view does it: only views can open windows).
    @Published var modelManagerRequested = false

    private var originals: [TranscriptFormat: String] = [:]
    private var segments: [TranscriptSegment] = []
    private var jobID = UUID()
    private var job: Task<Void, Never>?
    private var startedAt = Date()
    /// A file dropped before any model was installed; recognized once a model is ready.
    private var pendingURL: URL?
    private var sleepActivity: NSObjectProtocol?
    private var badgePercent: Int?

    init() {
        WhisperEngine.setLoggingEnabled(false)
        // The app was already approved by the user; the bundled ffmpeg must not trigger Gatekeeper again.
        if let ffmpeg = AppPaths.ffmpegURL {
            removexattr(ffmpeg.path, "com.apple.quarantine", 0)
        }
        Task.detached(priority: .utility) { WhisperEngine.warmUp() }

        modelID = defaults.string(forKey: "modelID") ?? ""
        language = defaults.string(forKey: "language") ?? "ru"
        prompt = defaults.string(forKey: "prompt") ?? ""
        skipSilence = defaults.object(forKey: "skipSilence") as? Bool ?? true
        beamSearch = defaults.object(forKey: "beamSearch") as? Bool ?? true
        format = TranscriptFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .text

        modelStore.onInstalled = { [weak self] id in
            self?.modelInstalled(id)
        }
        ensureValidModelSelection()
    }

    // MARK: - Model

    var selectedModelURL: URL? { modelStore.modelURL(for: modelID) }
    var modelName: String { modelStore.displayName(for: modelID) }

    /// Keeps a model that exists on disk selected; standard Whisper Turbo is preferred.
    func ensureValidModelSelection() {
        guard modelStore.modelURL(for: modelID) == nil else { return }
        let available = modelStore.availableModelIDs
        if let id = ModelCatalog.preferredOrder.first(where: available.contains) ?? available.first {
            modelID = id
        }
    }

    private func modelInstalled(_ id: String) {
        if selectedModelURL == nil { modelID = id }
        if let url = pendingURL {
            pendingURL = nil
            open(url)
        }
    }

    // MARK: - Job

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = L("Выберите аудио или видео")
        panel.prompt = L("Распознать")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    /// Starts recognition of a file (a running job is cancelled).
    func open(_ url: URL) {
        modelStore.refresh()
        ensureValidModelSelection()
        guard let modelURL = selectedModelURL else {
            pendingURL = url
            modelManagerRequested = true
            return
        }
        cancelJob()
        let id = UUID()
        jobID = id
        fileURL = url
        media = nil
        transcript = nil
        segments = []
        liveText = ""
        texts = [:]
        originals = [:]
        step = .opening
        stepProgress = nil
        recognitionStartedAt = nil
        startedAt = Date()
        elapsed = 0
        phase = .working
        beginBackgroundWork()

        let options = WhisperOptions(modelPath: modelURL.path, language: language, prompt: prompt, beamSearch: beamSearch,
                                     vadModelPath: skipSilence ? AppPaths.vadModelURL?.path : nil)
        let modelName = self.modelName
        job = Task { [weak self] in
            await self?.run(url: url, options: options, modelName: modelName, id: id)
        }
    }

    private func run(url: URL, options: WhisperOptions, modelName: String, id: UUID) async {
        do {
            let info = try await FFmpeg.probe(url)
            guard id == jobID else { return }
            media = info
            guard info.hasAudio else { throw MediaError.noAudio }
            step = .extracting
            stepProgress = 0

            let flag = CancelFlag()
            let worker = Task.detached(priority: .userInitiated) { [weak self] () throws -> (segments: [TranscriptSegment], language: String) in
                let work = AppPaths.makeTempDir("job")
                defer { try? FileManager.default.removeItem(at: work) }
                let samples = try await FFmpeg.extractAudioSamples(from: url, workDir: work, duration: info.duration) { p in
                    onMain { self?.setStep(.extracting, progress: p, job: id) }
                }
                if flag.isCancelled { throw WhisperError.cancelled }
                if WhisperEngine.isWarmingUp {
                    onMain { self?.setStep(.preparingGPU, progress: nil, job: id) }
                    while WhisperEngine.isWarmingUp && !flag.isCancelled {
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                WhisperEngine.warmUp()
                return try WhisperEngine.transcribe(samples: samples, options: options, stage: { stage in
                    onMain { self?.setStep(stage == .loadingModel ? .loadingModel : .recognizing, progress: stage == .recognizing ? 0 : nil, job: id) }
                }, onSegment: { segment in
                    onMain { self?.addSegment(segment, job: id) }
                }, progress: { p in
                    onMain { self?.setRecognitionProgress(p, job: id) }
                }, isCancelled: { flag.isCancelled })
            }
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                flag.cancel()
                worker.cancel()
            }
            guard id == jobID else { return }
            finish(result, info: info, modelName: modelName, skippedSilence: options.vadModelPath != nil)
        } catch {
            guard id == jobID else { return }
            endBackgroundWork()
            phase = .idle
            fileURL = nil
            media = nil
            if !Self.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setStep(_ newStep: Step, progress: Double?, job: UUID) {
        guard job == jobID, phase == .working else { return }
        step = newStep
        stepProgress = progress
        if newStep == .recognizing, recognitionStartedAt == nil { recognitionStartedAt = Date() }
    }

    private func setRecognitionProgress(_ value: Double, job: UUID) {
        guard job == jobID, phase == .working, step == .recognizing else { return }
        stepProgress = value
        updateBadge(Int(value * 100))
    }

    private func addSegment(_ segment: TranscriptSegment, job: UUID) {
        guard job == jobID, phase == .working else { return }
        segments.append(segment)
        liveText = format.render(segments)
    }

    private func finish(_ result: (segments: [TranscriptSegment], language: String), info: MediaInfo, modelName: String,
                        skippedSilence: Bool) {
        endBackgroundWork()
        elapsed = Date().timeIntervalSince(startedAt)
        guard !result.segments.isEmpty else {
            phase = .idle
            fileURL = nil
            errorMessage = skippedSilence
                ? L("Речь не найдена. Проверьте язык распознавания или выключите «Пропускать тишину и музыку» в настройках.")
                : L("Речь не найдена. Проверьте язык распознавания или попробуйте другую модель.")
            return
        }
        segments = result.segments
        transcript = Transcript(segments: result.segments, language: result.language, modelName: modelName, duration: info.duration)
        for format in TranscriptFormat.allCases {
            originals[format] = format.render(result.segments)
        }
        texts = originals
        phase = .done
        if !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    func cancel() {
        guard phase == .working else { return }
        cancelJob()
        phase = .idle
        fileURL = nil
        media = nil
        segments = []
        liveText = ""
    }

    /// Back to the drop zone.
    func reset() {
        cancelJob()
        phase = .idle
        fileURL = nil
        media = nil
        transcript = nil
        segments = []
        liveText = ""
        texts = [:]
        originals = [:]
    }

    /// The same file again with the current model and language.
    func retranscribe() {
        guard let url = fileURL, phase != .working else { return }
        open(url)
    }

    private func cancelJob() {
        job?.cancel()
        job = nil
        jobID = UUID()  // late reports of the old job are ignored
        endBackgroundWork()
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case MediaError.cancelled = error { return true }
        if case WhisperError.cancelled = error { return true }
        return false
    }

    /// Long recordings take a while: the Mac must not fall asleep, and the Dock icon shows the progress.
    private func beginBackgroundWork() {
        guard sleepActivity == nil else { return }
        sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                              reason: "Speech recognition")
    }

    private func endBackgroundWork() {
        if let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
        updateBadge(nil)
    }

    private func updateBadge(_ percent: Int?) {
        guard percent != badgePercent else { return }
        badgePercent = percent
        NSApp.dockTile.badgeLabel = percent.map { "\($0)%" }
    }

    /// Estimated time left, once recognition has run long enough to judge its speed.
    func remainingTime(at now: Date) -> TimeInterval? {
        guard step == .recognizing, let start = recognitionStartedAt, let progress = stepProgress,
              progress >= 0.05, progress < 1 else { return nil }
        let spent = now.timeIntervalSince(start)
        guard spent >= 2 else { return nil }
        return spent / progress * (1 - progress)
    }

    // MARK: - Result

    /// What is shown, copied, saved and shared.
    var currentText: String {
        phase == .done ? texts[format] ?? "" : liveText
    }

    var isEdited: Bool {
        phase == .done && texts[format] != originals[format]
    }

    func revertEdits() {
        texts[format] = originals[format]
    }

    var wordCountText: String {
        let count = wordCount(phase == .done ? texts[.text] ?? "" : segments.map(\.text).joined(separator: " "))
        return pluralize(count, "слово", "слова", "слов", en: "word", "words")
    }

    /// "Русский" or "Английский (определён автоматически)".
    var languageText: String {
        guard let transcript else { return "" }
        let name = WhisperEngine.languageName(transcript.language)
        return language == "auto" ? L("%@, определён автоматически", name) : name
    }

    /// Suggested file name without extension, after the recording.
    var baseName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? L("Расшифровка")
    }

    func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentText, forType: .string)
    }

    func save(completion: @escaping (Bool) -> Void = { _ in }) {
        guard phase == .done else { return }
        let panel = NSSavePanel()
        panel.title = L("Сохранить расшифровку")
        panel.nameFieldStringValue = baseName + "." + format.fileExtension
        panel.allowedContentTypes = [format == .srt ? UTType(filenameExtension: "srt") ?? .plainText : .plainText]
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return completion(false) }
            completion(self.write(to: url))
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    /// Writes the shown text as UTF-8.
    @discardableResult
    func write(to url: URL) -> Bool {
        do {
            try currentText.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            errorMessage = L("Не удалось сохранить файл: %@", error.localizedDescription)
            return false
        }
    }
}
