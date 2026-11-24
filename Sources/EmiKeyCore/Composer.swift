import Foundation
// STUB — owned by agent "telex". Pass-through until implemented.
public final class Composer {
    public var settings: ComposerSettings
    public init(telex: TelexTransforming, pinyin: PinyinLookup, english: EnglishLexicon, settings: ComposerSettings, learnedFile: URL?) {
        self.settings = settings
    }
    /// precedingText: text before the cursor in the client (may be nil if the app hides it).
    public func handle(_ key: KeyInput, precedingText: String?) -> ComposerOutput {
        if case .char(let c) = key { return ComposerOutput(commit: String(c)) }
        return ComposerOutput(handled: false)
    }
    /// Pick candidate index (0-based) by mouse click in the candidate bar.
    public func pick(_ index: Int) -> ComposerOutput { ComposerOutput() }
    /// Focus lost / app switched: returns text to commit, clears state.
    public func flush() -> String { "" }
}
