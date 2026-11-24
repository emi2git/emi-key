import Cocoa
import EmiKeyCore

/// Shared engine + persisted settings. One Composer for the process (the dictionaries are big);
/// it is flushed whenever the focused client changes.
final class AppState {
    static let shared = AppState()
    static let bundleID = "com.emi2git.inputmethod.EmiKey"

    let defaults: UserDefaults
    let composer: Composer
    let learnedFile: URL
    /// Test hook (`defaults write com.emi2git.inputmethod.EmiKey ForceHidden -bool YES`): treat every app as one
    /// that hides its text, to exercise the marked-text fallback. Re-read when a text field gains focus.
    var forceHidden = false

    /// Apps whose reported cursor never moves; they get marked (underlined) text instead of in-place editing.
    /// Ghostty is known up front so the very first word there works too.
    private lazy var untracked: Set<String> = Set(defaults.stringArray(forKey: "UntrackedApps") ?? [])
        .union(["com.mitchellh.ghostty"])
    func isUntracked(_ id: String?) -> Bool { id.map { untracked.contains($0) } ?? false }
    func markUntracked(_ id: String?) {
        guard let id, !untracked.contains(id) else { return }
        untracked.insert(id)
        defaults.set(Array(untracked), forKey: "UntrackedApps")
    }

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
        set { composer.settings.traditional = newValue; defaults.set(newValue, forKey: "traditional") }
    }
    var toneStyle: ToneStyle {
        get { composer.settings.toneStyle }
        set { composer.settings.toneStyle = newValue; defaults.set(newValue == .old ? "old" : "new", forKey: "toneStyle") }
    }
}
