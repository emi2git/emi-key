import Carbon
import Foundation

/// Register / enable / select Emi Key without touching System Settings.
///   EmiKey --install   register this bundle, enable it, select it
///   EmiKey --select    select it (must already be enabled)
///   EmiKey --disable   disable it
enum InputSources {
    static func sources(_ id: String = AppState.bundleID, all: Bool = true) -> [TISInputSource] {
        let filter = [kTISPropertyBundleID as String: id] as CFDictionary
        return (TISCreateInputSourceList(filter, all)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    static func prop<T>(_ s: TISInputSource, _ key: CFString) -> T? {
        guard let p = TISGetInputSourceProperty(s, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? T
    }

    static func run(_ args: [String]) -> Int32 {
        let bundle = Bundle.main.bundleURL
        if args.contains("--install") {
            let r = TISRegisterInputSource(bundle as CFURL)
            print("register \(bundle.path): \(r == noErr ? "ok" : "error \(r)")")
        }
        let list = sources()
        if list.isEmpty { print("Emi Key input source not found"); return 1 }
        var status: Int32 = 0
        for s in list {
            let id: String = prop(s, kTISPropertyInputSourceID) ?? "?"
            if args.contains("--disable") {
                print("disable \(id): \(TISDisableInputSource(s))")
                continue
            }
            if args.contains("--install") {
                let r = TISEnableInputSource(s); print("enable \(id): \(r == noErr ? "ok" : "error \(r)")")
                if r != noErr { status = 1 }
            }
            let selectable: Bool = prop(s, kTISPropertyInputSourceIsSelectCapable) ?? false
            if selectable && (args.contains("--install") || args.contains("--select")) {
                // Right after registering, TIS often answers paramErr (-50) once; retry.
                var r = TISSelectInputSource(s)
                for _ in 0..<5 where r != noErr { Thread.sleep(forTimeInterval: 0.5); r = TISSelectInputSource(s) }
                print("select \(id): \(r == noErr ? "ok" : "error \(r)")")
                if r != noErr { status = 1 }
            }
        }
        return status
    }
}
