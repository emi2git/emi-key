import Foundation

/// Builds the real engines from a resources folder (app bundle Resources, or test fixtures).
public enum Engines {
    public static func composer(resources: URL, settings: ComposerSettings = .init(), learnedFile: URL? = nil) -> Composer {
        Composer(telex: TelexEngine(),
                 pinyin: PinyinEngine(resources: resources),
                 english: EnglishWords(resources: resources),
                 settings: settings,
                 learnedFile: learnedFile)
    }
}
