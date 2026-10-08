import Foundation
import CWhisper

public struct WhisperOptions: Sendable {
    public var modelPath: String
    /// ISO code ("ru", "en", ...) or "auto".
    public var language: String
    /// Names and terms that appear in the recording; prepended to every 30-second window.
    public var prompt: String
    /// Beam search: slower, fewer mistakes.
    public var beamSearch: Bool
    /// Voice activity detection (Silero): skips silence and music, fewer made-up phrases.
    public var vadModelPath: String?
    public var useGPU: Bool
    public var threads: Int

    public init(modelPath: String, language: String = "ru", prompt: String = "", beamSearch: Bool = true,
                vadModelPath: String? = nil, useGPU: Bool = WhisperEngine.gpuAvailable, threads: Int = WhisperEngine.defaultThreads) {
        self.modelPath = modelPath
        self.language = language
        self.prompt = prompt
        self.beamSearch = beamSearch
        self.vadModelPath = vadModelPath
        self.useGPU = useGPU
        self.threads = threads
    }
}

public enum WhisperError: LocalizedError {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case failed(Int32)
    case cancelled
    case emptyAudio

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path): return L("Файл модели не найден: %@", "\(path)")
        case .modelLoadFailed(let name): return L("Не удалось загрузить модель «%@». Возможно, файл поврежден: удалите модель и скачайте ее заново", "\(name)")
        case .failed(let code): return L("Ошибка распознавания (код %@)", "\(code)")
        case .cancelled: return L("Распознавание отменено")
        case .emptyAudio: return L("Звуковая дорожка пустая")
        }
    }
}

/// Speech recognition with whisper.cpp (Metal on Apple Silicon).
public enum WhisperEngine {
    public enum Stage: Sendable {
        case loadingModel
        case recognizing
    }

    public static var defaultThreads: Int {
        max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2))
    }

    /// Metal is used on Apple Silicon; Intel Macs run on the CPU.
    public static var gpuAvailable: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    public static var version: String { String(cString: whisper_version()) }

    private static let warmUpLock = NSLock()
    private static var warmUpState = 0 // 0 = not started, 1 = running, 2 = done

    /// True while the GPU kernels are being compiled (only after installing or updating the app).
    public static var isWarmingUp: Bool {
        warmUpLock.lock()
        defer { warmUpLock.unlock() }
        return warmUpState == 1
    }

    /// Initializes the Metal backend so its kernels are compiled (and cached by macOS) before the first
    /// recognition. The first launch of a new app build takes ~10-30 s; later launches are instant.
    public static func warmUp() {
        guard gpuAvailable else { return }
        warmUpLock.lock()
        guard warmUpState == 0 else {
            warmUpLock.unlock()
            return
        }
        warmUpState = 1
        warmUpLock.unlock()
        if let device = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU),
           let backend = ggml_backend_dev_init(device, nil) {
            ggml_backend_free(backend)
        }
        warmUpLock.lock()
        warmUpState = 2
        warmUpLock.unlock()
    }

    /// Silences whisper.cpp's own log output (model loading details etc.).
    public static func setLoggingEnabled(_ enabled: Bool) {
        if enabled {
            whisper_log_set(nil, nil)
        } else {
            whisper_log_set({ _, _, _ in }, nil)
        }
    }

    // MARK: - Languages

    /// Languages shown first in the picker (besides "auto").
    public static let commonLanguageCodes = ["ru", "en", "uk", "be", "kk", "uz", "hy", "ka", "az", "de", "fr", "es", "it",
                                             "pt", "pl", "tr", "zh", "ja", "ko", "ar", "he"]

    /// Every language Whisper knows: (code, name in the interface language), sorted by name.
    public static let allLanguages: [(code: String, name: String)] = {
        (0...whisper_lang_max_id()).compactMap { id -> (code: String, name: String)? in
            guard let code = whisper_lang_str(id).map({ String(cString: $0) }) else { return nil }
            return (code, languageName(code))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    /// "Русский", "Английский", ... (or English names in the English interface).
    public static func languageName(_ code: String) -> String {
        if code == "auto" { return L("Определить автоматически") }
        let locale = Locale(identifier: Localization.current)
        // Whisper uses a few non-standard codes.
        let isoCode = ["jw": "jv"][code] ?? code
        if let name = locale.localizedString(forLanguageCode: isoCode), name.lowercased() != isoCode {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        let id = whisper_lang_id(code)
        if id >= 0, let full = whisper_lang_str_full(id) {
            return String(cString: full).capitalized
        }
        return code
    }

    // MARK: - Recognition

    private final class Callbacks {
        let progress: (Double) -> Void
        let isCancelled: () -> Bool
        let onSegment: (TranscriptSegment) -> Void
        var filter = SegmentFilter()

        init(progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool, onSegment: @escaping (TranscriptSegment) -> Void) {
            self.progress = progress
            self.isCancelled = isCancelled
            self.onSegment = onSegment
        }
    }

    /// One recognition at a time: a job that is being cancelled finishes before the next one loads its model.
    private static let runLock = NSLock()

    /// True while a recognition or the GPU warm-up holds whisper.cpp's Metal resources.
    public static var isBusy: Bool {
        guard runLock.try() else { return true }
        runLock.unlock()
        return isWarmingUp
    }

    /// Waits at most `timeout` seconds until a cancelled recognition and the GPU warm-up have let go of the GPU.
    /// ggml frees its Metal devices when the process exits and aborts if a context still holds GPU buffers then,
    /// so the app calls this before quitting. Returns false when the time ran out.
    @discardableResult
    public static func waitUntilIdle(timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        guard runLock.lock(before: deadline) else { return false }
        runLock.unlock()
        while isWarmingUp {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
    }

    /// Runs recognition on 16 kHz mono samples. Blocking — call from a background thread.
    /// `onSegment` receives phrases as soon as they are recognized (already filtered).
    public static func transcribe(
        samples: [Float], options: WhisperOptions,
        stage: @escaping (Stage) -> Void = { _ in },
        onSegment: @escaping (TranscriptSegment) -> Void = { _ in },
        progress: @escaping (Double) -> Void = { _ in },
        isCancelled: @escaping () -> Bool = { false }
    ) throws -> (segments: [TranscriptSegment], language: String) {
        guard !samples.isEmpty else { throw WhisperError.emptyAudio }
        guard FileManager.default.fileExists(atPath: options.modelPath) else {
            throw WhisperError.modelNotFound(options.modelPath)
        }
        runLock.lock()
        defer { runLock.unlock() }
        if isCancelled() { throw WhisperError.cancelled }

        stage(.loadingModel)
        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = options.useGPU
        contextParams.flash_attn = options.useGPU
        guard let ctx = whisper_init_from_file_with_params(options.modelPath, contextParams) else {
            throw WhisperError.modelLoadFailed(URL(fileURLWithPath: options.modelPath).lastPathComponent)
        }
        defer { whisper_free(ctx) }
        if isCancelled() { throw WhisperError.cancelled }
        stage(.recognizing)

        var params = whisper_full_default_params(options.beamSearch ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(options.threads)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.suppress_blank = true
        params.suppress_nst = true
        params.temperature = 0
        params.temperature_inc = 0.2
        if options.beamSearch {
            params.beam_search.beam_size = 5
        } else {
            params.greedy.best_of = 5
        }

        // C strings must stay alive during whisper_full.
        var allocated: [UnsafeMutablePointer<CChar>] = []
        defer { allocated.forEach { free($0) } }
        func cString(_ s: String) -> UnsafePointer<CChar> {
            let p = strdup(s)!
            allocated.append(p)
            return UnsafePointer(p)
        }

        params.language = cString(options.language.isEmpty ? "auto" : options.language)
        params.detect_language = false
        let prompt = options.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            params.initial_prompt = cString(prompt)
            params.carry_initial_prompt = true
        }
        if let vad = options.vadModelPath, FileManager.default.fileExists(atPath: vad) {
            params.vad = true
            params.vad_model_path = cString(vad)
            var vadParams = whisper_vad_default_params()
            vadParams.threshold = 0.5
            vadParams.min_speech_duration_ms = 200
            vadParams.min_silence_duration_ms = 300
            vadParams.speech_pad_ms = 200
            params.vad_params = vadParams
        }

        let callbacks = Callbacks(progress: progress, isCancelled: isCancelled, onSegment: onSegment)
        let userData = Unmanaged.passUnretained(callbacks).toOpaque()
        params.new_segment_callback = { ctx, _, newCount, userData in
            guard let ctx, let userData else { return }
            let callbacks = Unmanaged<Callbacks>.fromOpaque(userData).takeUnretainedValue()
            let total = whisper_full_n_segments(ctx)
            for index in max(0, total - newCount)..<total {
                if let segment = WhisperEngine.readSegment(ctx, index), callbacks.filter.accept(segment) {
                    callbacks.onSegment(segment)
                }
            }
        }
        params.new_segment_callback_user_data = userData
        params.progress_callback = { _, _, value, userData in
            guard let userData else { return }
            Unmanaged<Callbacks>.fromOpaque(userData).takeUnretainedValue().progress(Double(value) / 100)
        }
        params.progress_callback_user_data = userData
        params.abort_callback = { userData in
            guard let userData else { return false }
            return Unmanaged<Callbacks>.fromOpaque(userData).takeUnretainedValue().isCancelled()
        }
        params.abort_callback_user_data = userData
        params.encoder_begin_callback = { _, _, userData in
            guard let userData else { return true }
            return !Unmanaged<Callbacks>.fromOpaque(userData).takeUnretainedValue().isCancelled()
        }
        params.encoder_begin_callback_user_data = userData

        let status = samples.withUnsafeBufferPointer { buffer in
            whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
        }
        withExtendedLifetime(callbacks) {}
        if isCancelled() { throw WhisperError.cancelled }
        guard status == 0 else { throw WhisperError.failed(status) }

        let detected = String(cString: whisper_lang_str(whisper_full_lang_id(ctx)))
        var filter = SegmentFilter()
        let segments = (0..<whisper_full_n_segments(ctx)).compactMap { readSegment(ctx, $0) }.filter { filter.accept($0) }
        return (segments, detected)
    }

    /// Text and timing of one segment. Text is decoded leniently: a segment may end inside a UTF-8 character.
    static func readSegment(_ ctx: OpaquePointer, _ index: Int32) -> TranscriptSegment? {
        guard let cText = whisper_full_get_segment_text(ctx, index) else { return nil }
        let bytes = UnsafeBufferPointer(start: UnsafeRawPointer(cText).assumingMemoryBound(to: UInt8.self), count: strlen(cText))
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let start = Double(whisper_full_get_segment_t0(ctx, index)) / 100
        let end = max(start, Double(whisper_full_get_segment_t1(ctx, index)) / 100)
        return TranscriptSegment(start: start, end: end, text: text)
    }
}

/// Removes typical Whisper hallucinations: credits of subtitle authors on silence, "[музыка]", a phrase
/// repeated over and over.
public struct SegmentFilter {
    static let patterns: [String] = [
        "dimatorzok", "dima torzok", "субтитры сделал", "субтитры делал", "субтитры создавал", "субтитры подготовил",
        "субтитры подогнал", "редактор субтитров", "корректор а.", "а.синецкая", "а. синецкая", "субтитры:",
        "amara.org", "subtitles by",
    ]
    /// Dropped only when they are the whole segment (they can also be said for real).
    static let wholeSegmentPatterns: Set<String> = [
        "продолжение следует", "продолжение следует...", "продолжение следует…",
    ]

    private var previous: String?

    public init() {}

    public mutating func accept(_ segment: TranscriptSegment) -> Bool {
        let text = segment.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.patterns.contains(where: { text.contains($0) }) { return false }
        if Self.wholeSegmentPatterns.contains(text) { return false }
        // Whole segment in brackets: [музыка], (аплодисменты), *смех*
        if let first = text.first, let last = text.last,
           (first == "[" && last == "]") || (first == "(" && last == ")") || (first == "*" && last == "*") {
            return false
        }
        if text.allSatisfy({ !$0.isLetter && !$0.isNumber }) { return false }
        // A long phrase right after itself is a decoding loop, not speech.
        if text == previous, text.split(separator: " ").count >= 4 { return false }
        previous = text
        return true
    }
}
