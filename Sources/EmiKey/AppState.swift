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
    /// `defaults write com.emi2git.inputmethod.EmiKey DebugLog -bool YES`: log cursor/text details (test only —
    /// they contain what is typed). Re-read when a text field gains focus.
    var debug = false
    /// `KeyLog` (set by the e2e harness): one content-free line per key (handled / delete count / marked mode),
    /// so the harness can tell Emi Key saw its keys. Off by default: nothing is logged per key.
    var keyLog = false

    /// Terminals: a key that ends a composition is dropped (or replaced by the committed text), so Enter/Tab/Esc are
    /// sent together with the committed word; Esc always belongs to the program (never a flip); the text they report
    /// is the screen grid, so context comes from Emi Key's own word memory.
    /// `defaults write com.emi2git.inputmethod.EmiKey PtyApps -array-add <bundle id>` adds more.
    private lazy var terminals: Set<String> = Set(defaults.stringArray(forKey: "PtyApps") ?? [])
        .union(["com.apple.Terminal", "com.mitchellh.ghostty"])
    func isTerminal(_ id: String?) -> Bool { id.map { terminals.contains($0) } ?? false }

    /// Apps whose reported text is not the field's (WeChat 4 reports e.g. its placeholder): context comes from Emi
    /// Key's own word memory, and a committed word is never flipped there.
    private let ownTextHidden: Set<String> = ["com.tencent.xinWeChat"]
    func readsContext(_ id: String?) -> Bool { !isTerminal(id) && !(id.map { ownTextHidden.contains($0) } ?? false) }

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
