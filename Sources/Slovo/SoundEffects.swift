import Foundation
import AudioToolbox

/// Short sounds at the moments that matter, the same in all the author's apps. They are macOS's own interface sounds,
/// read from the system at run time (never copied into the app) and played the way the system plays them: at the
/// alert volume of Sound settings, through the device chosen there for sound effects, and only while "Play user
/// interface sound effects" is on. If a sound is missing, a classic alert sound from /System/Library/Sounds plays
/// the same way instead. The switch is in Settings.
enum SoundEffects {
    enum Event {
        /// Long work finished: the transcript is ready, a model is installed.
        case success
        /// Something went wrong.
        case failure
        /// Long work started: recognition, a model download.
        case start
        /// A small confirmation: the text is copied.
        case tick
        /// Something deleted: a model.
        case delete
        /// Sent away: saved to a file, shared.
        case send

        /// Path in the folder of the system's interface sounds.
        fileprivate var file: String {
            switch self {
            case .success: return "system/head_gestures_double_nod.caf"
            case .failure: return "system/head_gestures_double_shake.caf"
            case .start: return "system/begin_record.caf"
            case .tick: return "system/head_gestures_partial_nod.caf"
            case .delete: return "dock/poof item off dock.aif"
            case .send: return "system/SentMessage.caf"
            }
        }

        /// A sound of /System/Library/Sounds.
        fileprivate var fallback: String {
            switch self {
            case .success: return "Glass"
            case .failure: return "Basso"
            case .start, .tick: return "Tink"
            case .delete: return "Pop"
            case .send: return "Purr"
            }
        }
    }

    static let defaultsKey = "soundEffects"

    /// Plays nothing while the switch in Settings is off (it is on by default).
    @MainActor
    static func play(_ event: Event) {
        guard UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true else { return }
        DebugHooks.State.shared.sounds.append("\(event)")
        // Reading a sound from disk the first time must not hold up the window.
        queue.async {
            if let id = soundID(for: event) { AudioServicesPlaySystemSound(id) }
        }
    }

    private static let folder = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds")
    private static let queue = DispatchQueue(label: "SoundEffects", qos: .userInitiated)
    /// Every sound is opened once; nil when macOS has neither file. Used on `queue` only.
    private static var ids: [Event: SystemSoundID?] = [:]

    private static func soundID(for event: Event) -> SystemSoundID? {
        if let id = ids[event] { return id }
        let files = [folder.appendingPathComponent(event.file), URL(fileURLWithPath: "/System/Library/Sounds/\(event.fallback).aiff")]
        let id = files.lazy.compactMap(makeSoundID).first
        ids.updateValue(id, forKey: event)
        return id
    }

    private static func makeSoundID(_ url: URL) -> SystemSoundID? {
        var id: SystemSoundID = 0
        guard FileManager.default.fileExists(atPath: url.path), AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else {
            return nil
        }
        // An interface sound, silent while "Play user interface sound effects" is off (the default, said aloud).
        var isUISound: UInt32 = 1
        AudioServicesSetProperty(kAudioServicesPropertyIsUISound, UInt32(MemoryLayout<SystemSoundID>.size), &id,
                                 UInt32(MemoryLayout<UInt32>.size), &isUISound)
        return id
    }
}
