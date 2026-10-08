import Foundation
import TransCore

// Command line tool for checking recognition without the UI:
//   slovo-cli <file> [--model <id or path>] [--lang ru|en|auto|…] [--format text|timecodes|srt]
//                [--no-vad] [--greedy] [--prompt "names, terms"] [--quiet]
// The transcript goes to stdout; progress and live phrases go to stderr.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}
func flag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}

let modelArgument = option("--model")
let language = option("--lang") ?? "ru"
let format = TranscriptFormat(rawValue: option("--format") ?? "text") ?? .text
let prompt = option("--prompt") ?? ""
let useVAD = !flag("--no-vad")
let greedy = flag("--greedy")
let quiet = flag("--quiet")
guard let path = arguments.first else {
    fail("usage: slovo-cli <file> [--model <id or path>] [--lang ru] [--format text|timecodes|srt] [--no-vad] [--greedy] [--prompt …]")
}

let modelPath: String = {
    if let modelArgument {
        if let info = ModelCatalog.model(id: modelArgument) { return info.localURL.path }
        return modelArgument
    }
    let installed = ModelCatalog.preferredOrder.compactMap(ModelCatalog.model(id:)).first(where: \.isDownloaded)
        ?? ModelCatalog.models.first(where: \.isDownloaded)
    guard let installed else { fail("no model installed in \(AppPaths.modelsDir.path)") }
    return installed.localURL.path
}()

WhisperEngine.setLoggingEnabled(ProcessInfo.processInfo.environment["SLOVO_WHISPER_LOG"] != nil)
let url = URL(fileURLWithPath: path)
let started = Date()
let done = DispatchSemaphore(value: 0)

Task.detached {
    do {
        let info = try await FFmpeg.probe(url)
        log("file: \(url.lastPathComponent) · \(info.summary) · audio: \(info.hasAudio)")
        guard info.hasAudio else { throw MediaError.noAudio }
        let work = AppPaths.makeTempDir("cli")
        defer { try? FileManager.default.removeItem(at: work) }
        let samples = try await FFmpeg.extractAudioSamples(from: url, workDir: work, duration: info.duration)
        let decoded = Date()
        log(String(format: "audio: %.1f s decoded in %.2f s", Double(samples.count) / 16000, decoded.timeIntervalSince(started)))
        WhisperEngine.warmUp()
        log(String(format: "gpu ready in %.2f s", Date().timeIntervalSince(decoded)))
        let options = WhisperOptions(modelPath: modelPath, language: language, prompt: prompt, beamSearch: !greedy,
                                     vadModelPath: useVAD ? AppPaths.vadModelURL?.path : nil)
        log("model: \(URL(fileURLWithPath: modelPath).lastPathComponent) · lang: \(language) · vad: \(options.vadModelPath != nil) · beam: \(!greedy)")
        let recognitionStart = Date()
        var lastPercent = -10
        let result = try WhisperEngine.transcribe(samples: samples, options: options, stage: { stage in
            if case .recognizing = stage {
                log(String(format: "model loaded in %.2f s", Date().timeIntervalSince(recognitionStart)))
            }
        }, onSegment: { segment in
            if !quiet { log(String(format: "  [%7.2f → %7.2f] %@", segment.start, segment.end, segment.text)) }
        }, progress: { value in
            let percent = Int(value * 100)
            if percent >= lastPercent + 10 {
                lastPercent = percent
                log("  \(percent)%")
            }
        })
        let elapsed = Date().timeIntervalSince(recognitionStart)
        log(String(format: "recognized in %.2f s (%.1fx realtime) · language: %@ · segments: %d",
                   elapsed, Double(samples.count) / 16000 / max(elapsed, 0.001), result.language, result.segments.count))
        print(format.render(result.segments))
    } catch {
        log("error: \(error.localizedDescription)")
        exit(1)
    }
    done.signal()
}
done.wait()
