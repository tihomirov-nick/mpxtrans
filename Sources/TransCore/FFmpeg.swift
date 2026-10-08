import Foundation

public enum MediaError: LocalizedError {
    case ffmpegNotFound
    case unreadable(String)
    case noAudio
    case failed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .ffmpegNotFound: return L("Не найден встроенный ffmpeg. Переустановите приложение")
        case .unreadable(let details):
            let text = L("Не удалось открыть файл как аудио или видео")
            return details.isEmpty ? text : text + "\n" + details
        case .noAudio: return L("В файле нет звуковой дорожки, распознавать нечего")
        case .failed(let details): return L("Ошибка ffmpeg:\n%@", "\(details)")
        case .cancelled: return L("Отменено")
        }
    }
}

/// Information about a media file, parsed from ffmpeg output.
public struct MediaInfo: Sendable {
    public var url: URL
    public var duration: Double
    public var hasVideo: Bool
    public var hasAudio: Bool
    public var width: Int
    public var height: Int
    public var videoCodec: String?
    public var audioCodec: String?

    /// "12:34 · AAC" or "12:34 · 1920×1080 · H264".
    public var summary: String {
        var parts = [formatDuration(duration)]
        if hasVideo, width > 0, height > 0 { parts.append("\(width)×\(height)") }
        if let codec = hasVideo ? videoCodec : audioCodec { parts.append(codec.uppercased()) }
        return parts.joined(separator: " · ")
    }
}

/// Runs the bundled ffmpeg binary.
public enum FFmpeg {
    public static func executable() throws -> URL {
        guard let url = AppPaths.ffmpegURL else { throw MediaError.ffmpegNotFound }
        return url
    }

    public struct Result {
        public let status: Int32
        public let stderr: String
    }

    /// Runs ffmpeg with the arguments. `onStdoutLine` receives lines printed to stdout (used with `-progress pipe:1`).
    /// Cancelling the calling task terminates the process.
    @discardableResult
    public static func run(_ arguments: [String], allowFailure: Bool = false, onStdoutLine: ((String) -> Void)? = nil) async throws -> Result {
        let executable = try executable()
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let collector = OutputCollector(onLine: onStdoutLine)
        let readers = DispatchGroup()

        let result: Result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
                process.terminationHandler = { finished in
                    readers.notify(queue: .global()) {
                        collector.finish()
                        continuation.resume(returning: Result(status: finished.terminationStatus, stderr: collector.stderrText))
                    }
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: MediaError.failed(error.localizedDescription))
                    return
                }
                for (pipe, isStdout) in [(stdoutPipe, true), (stderrPipe, false)] {
                    readers.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let handle = pipe.fileHandleForReading
                        while true {
                            let data = handle.availableData
                            if data.isEmpty { break }
                            if isStdout { collector.appendStdout(data) } else { collector.appendStderr(data) }
                        }
                        readers.leave()
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        if Task.isCancelled { throw MediaError.cancelled }
        if result.status != 0 && !allowFailure {
            throw MediaError.failed(lastLines(result.stderr, count: 8))
        }
        return result
    }

    static func lastLines(_ text: String, count: Int) -> String {
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.suffix(count).joined(separator: "\n")
    }

    /// Parses `out_time_us=` lines of `-progress` output into seconds.
    static func progressSeconds(_ line: String) -> Double? {
        guard line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") else { return nil }
        guard let value = Double(line.split(separator: "=").last ?? "") else { return nil }
        return value / 1_000_000
    }

    // MARK: - Probe

    public static func probe(_ url: URL) async throws -> MediaInfo {
        let result = try await run(["-hide_banner", "-nostdin", "-i", url.path], allowFailure: true)
        guard var info = parseProbe(result.stderr, url: url) else {
            throw MediaError.unreadable(lastLines(result.stderr, count: 2))
        }
        if info.duration <= 0, info.hasAudio {
            info.duration = try await measureDuration(url)
        }
        return info
    }

    /// Decodes the file quickly to find its duration when the container does not store it.
    static func measureDuration(_ url: URL) async throws -> Double {
        var last = 0.0
        _ = try await run(["-hide_banner", "-nostdin", "-loglevel", "error", "-i", url.path, "-map", "0:a:0?",
                           "-c", "copy", "-f", "null", "-progress", "pipe:1", "-nostats", "-"], allowFailure: true) { line in
            if let t = progressSeconds(line) { last = max(last, t) }
        }
        return last
    }

    static func parseProbe(_ text: String, url: URL) -> MediaInfo? {
        var duration = 0.0
        var hasVideo = false, hasAudio = false
        var width = 0, height = 0
        var videoCodec: String?, audioCodec: String?
        var rotation = 0
        var inVideoStream = false

        for line in text.components(separatedBy: .newlines) {
            if let match = firstMatch(#"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)"#, in: line),
               let h = Double(match[1]), let m = Double(match[2]), let s = Double(match[3]) {
                duration = h * 3600 + m * 60 + s
            }
            if line.contains("Stream #") {
                inVideoStream = false
                if line.contains("Video:") && !line.contains("(attached pic)") && !hasVideo {
                    hasVideo = true
                    inVideoStream = true
                    videoCodec = firstMatch(#"Video: ([A-Za-z0-9_]+)"#, in: line)?[1]
                    if let size = firstMatch(#", (\d{2,5})x(\d{2,5})"#, in: line) {
                        width = Int(size[1]) ?? 0
                        height = Int(size[2]) ?? 0
                    }
                } else if line.contains("Audio:") && !hasAudio {
                    hasAudio = true
                    audioCodec = firstMatch(#"Audio: ([A-Za-z0-9_]+)"#, in: line)?[1]
                }
            } else if inVideoStream, let r = firstMatch(#"rotation of (-?\d+(?:\.\d+)?) degrees"#, in: line), let value = Double(r[1]) {
                rotation = Int(value.rounded())
            }
        }
        guard hasVideo || hasAudio else { return nil }
        let normalized = ((rotation % 360) + 360) % 360
        if normalized == 90 || normalized == 270 { swap(&width, &height) }
        return MediaInfo(url: url, duration: duration, hasVideo: hasVideo, hasAudio: hasAudio,
                         width: width, height: height, videoCodec: videoCodec, audioCodec: audioCodec)
    }

    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return (0..<match.numberOfRanges).map { i in
            guard let r = Range(match.range(at: i), in: text) else { return "" }
            return String(text[r])
        }
    }

    // MARK: - Audio for Whisper

    /// Decodes the first audio track to 16 kHz mono float samples. Silence is added at the beginning when the
    /// audio starts later than the video, so timecodes match the file's timeline.
    public static func extractAudioSamples(from url: URL, workDir: URL, duration: Double, progress: ((Double) -> Void)? = nil) async throws -> [Float] {
        let output = workDir.appendingPathComponent("audio.f32")
        try? FileManager.default.removeItem(at: output)
        defer { try? FileManager.default.removeItem(at: output) }
        try await run([
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-i", url.path,
            "-map", "0:a:0", "-vn", "-sn", "-dn",
            "-af", "aresample=async=1:first_pts=0",
            "-ac", "1", "-ar", "16000", "-c:a", "pcm_f32le", "-f", "f32le",
            "-progress", "pipe:1", "-nostats",
            output.path,
        ]) { line in
            if let t = progressSeconds(line), duration > 0 { progress?(min(1, t / duration)) }
        }
        // Mapped, so a long recording is not held in memory twice while it is copied.
        let data = try Data(contentsOf: output, options: .alwaysMapped)
        var samples = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.size)
        samples.withUnsafeMutableBytes { buffer in
            _ = data.copyBytes(to: buffer)
        }
        return samples
    }
}

/// Collects process output; splits stdout into lines.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrData = Data()
    private let onLine: ((String) -> Void)?

    init(onLine: ((String) -> Void)?) {
        self.onLine = onLine
    }

    func appendStdout(_ data: Data) {
        guard let onLine else { return }
        lock.lock()
        stdoutBuffer.append(data)
        var lines: [String] = []
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[stdoutBuffer.startIndex..<newline]
            lines.append(String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
        }
        lock.unlock()
        lines.forEach(onLine)
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        stderrData.append(data)
        if stderrData.count > 2_000_000 {
            stderrData = stderrData.suffix(1_000_000)
        }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        let rest = stdoutBuffer
        stdoutBuffer.removeAll()
        lock.unlock()
        if !rest.isEmpty, let onLine {
            onLine(String(decoding: rest, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    var stderrText: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: stderrData, as: UTF8.self)
    }
}
