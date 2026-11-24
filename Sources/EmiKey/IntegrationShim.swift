import EmiKeyCore

extension Composer {
    /// Characters to delete before the cursor, in UTF-16 units (for NSRange replacement).
    var deleteCount: Int { lastDeleteUTF16Count }
}
