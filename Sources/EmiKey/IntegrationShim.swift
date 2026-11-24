// INTEGRATION SHIM — remove at merge.
// The real Composer exposes `public var lastDeleteCount: Int`. Until then the app reads `deleteCount`
// through this adapter. At merge, change the body to `lastDeleteCount` (or delete this file and
// rename the single call site in InputController.swift).
import EmiKeyCore

extension Composer {
    var deleteCount: Int { 0 }
}
