import Cocoa
import InputMethodKit

let args = CommandLine.arguments
if args.contains(where: { ["--install", "--select", "--disable"].contains($0) }) {
    exit(InputSources.run(args))
}

let info = Bundle.main.infoDictionary ?? [:]
let connection = info["InputMethodConnectionName"] as? String ?? "com.emi2git.inputmethod.EmiKey_Connection"
guard let server = IMKServer(name: connection, bundleIdentifier: Bundle.main.bundleIdentifier ?? AppState.bundleID) else {
    FileHandle.standardError.write(Data("Emi Key: could not start IMKServer (run from the installed .app)\n".utf8))
    exit(1)
}
_ = server
_ = AppState.shared   // load dictionaries before the first key
NSApplication.shared.run()
