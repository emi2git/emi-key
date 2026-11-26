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
    /// `defaults write com.emi2git.inputmethod.EmiKey DebugLog -bool YES`: log cursor/text details (test only —
    /// they contain what is typed). Re-read when a text field gains focus.
    var debug = false
    /// `KeyLog` (set by the e2e harness): one content-free line per key (handled / delete count / marked mode),
    /// so the harness can tell Emi Key saw its keys. Off by default: nothing is logged per key.
    var keyLog = false

    /// Apps whose reported cursor never moves; they get marked (underlined) text instead of in-place editing.
    /// Ghostty is known up front so the very first word there works too.
    private lazy var untracked: Set<String> = Set(defaults.stringArray(forKey: "UntrackedApps") ?? [])

    func isUntracked(_ id: String?) -> Bool { id.map { (untracked.contains($0) || marked.contains($0)) && !blind.contains($0) } ?? false }

    /// Apps whose text fields ignore replacement ranges (WeChat 4, Qt: a replacement is inserted after the old text
    /// instead of over it). Words are composed as marked text there, and a committed word cannot be flipped with Esc.
    /// `defaults write com.emi2git.inputmethod.EmiKey MarkedApps -array-add <bundle id>` adds more.
    private lazy var marked: Set<String> = Set(defaults.stringArray(forKey: "MarkedApps") ?? []).union(["com.tencent.xinWeChat"])
    func isMarkedApp(_ id: String?) -> Bool { id.map { marked.contains($0) } ?? false }
    func markUntracked(_ id: String?) {
        guard let id, !untracked.contains(id), !blind.contains(id) else { return }
        untracked.insert(id)
        defaults.set(Array(untracked), forKey: "UntrackedApps")
    }

    /// Apps that apply in-place edits correctly but report a cursor/text that drifts from what is on screen
    /// (Terminal.app: its text is the screen grid). Emi Key edits them directly, trusting its own record of
    /// what it typed (cursor + recent text) instead of what the app reports. `defaults … BlindApps` adds more.
    private lazy var blind: Set<String> = Set(defaults.stringArray(forKey: "BlindApps") ?? []).union(["com.apple.Terminal"]).union(pty)
    func isBlind(_ id: String?) -> Bool { id.map { blind.contains($0) } ?? false }
    /// Terminals that ignore replacement ranges (Ghostty): an edit is sent as DEL characters + the new text,
    /// exactly what typing Backspace and the letters would send to the shell.
    private lazy var pty: Set<String> = Set(defaults.stringArray(forKey: "PtyApps") ?? []).union(["com.mitchellh.ghostty"])
    func isPty(_ id: String?) -> Bool { id.map { pty.contains($0) } ?? false }

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
        let pinyin = PinyinEngine(resources: resources), english = EnglishWords(resources: resources)
        composer = Composer(telex: TelexEngine(), pinyin: pinyin, english: english, settings: s, learnedFile: learnedFile)
        // Missing / unreadable dictionaries: without the English list every word would turn Vietnamese.
        // Then Emi Key types nothing itself — every key goes straight to the app.
        ready = pinyin.entryCount > 0 && english.count > 0
        if !ready { log.error("dictionaries missing: pass-through only") }
        log.notice("loaded in \(Int(pinyin.loadMillis), privacy: .public) ms")
    }

    /// False when the bundled dictionaries could not be loaded: every key is passed to the app untouched.
    let ready: Bool

    var traditional: Bool {
        get { composer.settings.traditional }
        set { composer.settings.traditional = newValue; defaults.set(newValue, forKey: "traditional") }
    }
    var toneStyle: ToneStyle {
        get { composer.settings.toneStyle }
        set { composer.settings.toneStyle = newValue; defaults.set(newValue == .old ? "old" : "new", forKey: "toneStyle") }
    }
}
