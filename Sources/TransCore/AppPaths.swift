import Foundation

/// File system locations used by the app.
public enum AppPaths {
    public static let appName = "Slovo"

    /// Whisper models are shared with Subline (formerly Subtits): a model downloaded in either app is available in
    /// both. Subline 2.0 moves ~/Library/Application Support/Subtits to Subline and leaves a link under the old name,
    /// so Subline/Models comes first and Subtits/Models (a Mac with an older Subtits) second; a new folder goes under
    /// Subline. `SLOVO_MODELS_DIR` points to another folder (for tests).
    public static var modelsDir: URL {
        if let custom = ProcessInfo.processInfo.environment["SLOVO_MODELS_DIR"], !custom.isEmpty {
            return ensureDir(URL(fileURLWithPath: custom, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let subline = base.appendingPathComponent("Subline/Models", isDirectory: true)
        let subtits = base.appendingPathComponent("Subtits/Models", isDirectory: true)
        if !isDirectory(subline), isDirectory(subtits) { return subtits }
        return ensureDir(subline)
    }

    /// A folder, or a link to one.
    static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    /// A fresh temporary directory for one job (extracted audio).
    public static func makeTempDir(_ prefix: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(appName)-\(prefix)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        return ensureDir(dir)
    }

    @discardableResult
    static func ensureDir(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Bundled resources

    /// Repository root when running from `.build` during development (directory containing Package.swift).
    static let devRoot: URL? = {
        var url = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<10 {
            guard let current = url else { return nil }
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current
            }
            url = current.deletingLastPathComponent()
        }
        return nil
    }()

    /// Silero VAD model shipped with the app (Contents/Resources), or `Resources/` in the repo during development.
    public static var vadModelURL: URL? {
        let name = "ggml-silero-v6.2.0.bin"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent(name)) }
        if let root = devRoot { candidates.append(root.appendingPathComponent("Resources").appendingPathComponent(name)) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The ffmpeg binary: bundled helper first, then the development copy, then a system install.
    public static var ffmpegURL: URL? {
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["SLOVO_FFMPEG"], !env.isEmpty {
            candidates.append(URL(fileURLWithPath: env))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ffmpeg"))
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exeDir.appendingPathComponent("ffmpeg"))
        }
        if let root = devRoot {
            candidates.append(root.appendingPathComponent("Vendor/ffmpeg/ffmpeg"))
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/ffmpeg"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
