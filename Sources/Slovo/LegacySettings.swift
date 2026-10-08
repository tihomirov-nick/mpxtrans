import Foundation

/// Slovo was called MPXTrans before 1.1 and kept its settings under another id. At the first launch they move over
/// once and the old settings are removed. MPXTrans also wrote the interface language it had picked into its own
/// language list; that entry is dropped, only a language chosen for the app in System Settings comes along.
enum LegacySettings {
    static let currentID = "com.slovo.app"

    static func migrate() {
        // A build with another id (BUNDLE_ID in build_app.sh) must not take the real MPXTrans settings away.
        let old = "com.mpxtrans.app"
        guard let id = Bundle.main.bundleIdentifier, id == currentID else { return }
        let defaults = UserDefaults.standard
        guard let domain = defaults.persistentDomain(forName: old) else { return }
        for key in ["modelID", "language", "prompt", "skipSilence", "beamSearch", "format"] where defaults.object(forKey: key) == nil {
            if let value = domain[key] { defaults.set(value, forKey: key) }
        }
        if let choice = domain["MPXTransLanguage"] as? String,
           defaults.persistentDomain(forName: id)?["AppleLanguages"] == nil {
            defaults.set([choice], forKey: "AppleLanguages")
        }
        defaults.removePersistentDomain(forName: old)
    }
}
