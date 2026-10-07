import Foundation

/// A phrase recognized by Whisper with its timing in seconds.
public struct TranscriptSegment: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// The result of recognition for one file.
public struct Transcript: Codable, Sendable {
    public var segments: [TranscriptSegment]
    /// Language code Whisper used (detected when the language was "auto").
    public var language: String
    public var modelName: String
    public var duration: Double

    public init(segments: [TranscriptSegment], language: String, modelName: String, duration: Double) {
        self.segments = segments
        self.language = language
        self.modelName = modelName
        self.duration = duration
    }
}

/// How the transcript is shown, copied and saved.
public enum TranscriptFormat: String, CaseIterable, Identifiable, Sendable {
    /// Plain text split into paragraphs at pauses.
    case text
    /// One phrase per line with its start time: "[01:23] …".
    case timecodes
    /// Subtitles.
    case srt

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .text: return L("Текст")
        case .timecodes: return L("Таймкоды")
        case .srt: return "SRT"
        }
    }

    public var fileExtension: String { self == .srt ? "srt" : "txt" }

    public func render(_ segments: [TranscriptSegment]) -> String {
        switch self {
        case .text: return TranscriptFormat.paragraphs(segments).joined(separator: "\n\n")
        case .timecodes:
            let hours = (segments.last?.end ?? 0) >= 3600
            return segments.map { "[\(TranscriptFormat.clock($0.start, hours: hours))] \($0.text)" }.joined(separator: "\n")
        case .srt:
            return segments.enumerated().map { index, segment in
                "\(index + 1)\n\(TranscriptFormat.srtTime(segment.start)) --> \(TranscriptFormat.srtTime(max(segment.end, segment.start + 0.5)))\n\(segment.text)"
            }.joined(separator: "\n\n") + (segments.isEmpty ? "" : "\n")
        }
    }

    /// A new paragraph starts after a finished sentence followed by a pause, or when the paragraph grows long.
    static func paragraphs(_ segments: [TranscriptSegment]) -> [String] {
        var result: [String] = []
        var current = ""
        var previousEnd = 0.0
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if !current.isEmpty {
                let endsSentence = current.last.map { ".!?…".contains($0) } ?? false
                let pause = segment.start - previousEnd
                if endsSentence && (pause >= 1.5 || current.count >= 600) {
                    result.append(current)
                    current = ""
                }
            }
            current += current.isEmpty ? text : " " + text
            previousEnd = segment.end
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// "01:23" or "1:01:23".
    static func clock(_ seconds: Double, hours: Bool) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600, m = (total / 60) % 60, s = total % 60
        return hours ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m + h * 60, s)
    }

    /// "00:01:02,345".
    static func srtTime(_ seconds: Double) -> String {
        let ms = Int((max(0, seconds) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }
}

/// Number of words in a text (sequences with at least one letter or digit).
public func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.count
}
