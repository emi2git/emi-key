import Cocoa
import EmiKeyCore

/// Shared engine + persisted settings. One Composer for the process (the dictionaries are big);
/// it is flushed whenever the focused client changes.
final class AppState {
    static let shared = AppState()
    static let bundleID = "com.emi2git.inputmethod.EmiKey"
    static let settingsChanged = Notification.Name("EmiKeySettingsChanged")

    let defaults: UserDefaults
    let composer: Composer
    let learnedFile: URL

    private init() {
        // A suite named after our own bundle id is our standard domain (UserDefaults refuses that name as a suite).
        defaults = Bundle.main.bundleIdentifier == Self.bundleID ? .standard : (UserDefaults(suiteName: Self.bundleID) ?? .standard)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Emi Key")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        learnedFile = dir.appendingPathComponent("learned.json")
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        var s = ComposerSettings()
        s.traditional = defaults.bool(forKey: "traditional")
        s.toneStyle = defaults.string(forKey: "toneStyle") == "old" ? .old : .new
        composer = Engines.composer(resources: resources, settings: s, learnedFile: learnedFile)
    }

    var traditional: Bool {
        get { composer.settings.traditional }
        set { composer.settings.traditional = newValue; defaults.set(newValue, forKey: "traditional"); changed() }
    }
    var toneStyle: ToneStyle {
        get { composer.settings.toneStyle }
        set { composer.settings.toneStyle = newValue; defaults.set(newValue == .old ? "old" : "new", forKey: "toneStyle"); changed() }
    }
    private func changed() { NotificationCenter.default.post(name: Self.settingsChanged, object: nil) }
}
