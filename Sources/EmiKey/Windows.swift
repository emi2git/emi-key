import Cocoa
import EmiKeyCore

/// Settings, Help and About windows. The IME is a background app, so it becomes an accessory app
/// while one of these is open.
enum Windows {
    private static var settings: NSWindow?
    private static var help: NSWindow?

    private static func bringFront(_ w: NSWindow) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        w.center()
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    private static func window(_ title: String, _ content: NSView) -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.contentView = content
        return w
    }

    static func showSettings() {
        if settings == nil { settings = window("Emi Key Settings", SettingsView()) }
        bringFront(settings!)
    }

    static func showHelp() {
        if help == nil {
            let text = """
            Just type — English, Vietnamese and Chinese with no switching.

            Vietnamese (Telex)
              vieetj → việt    tooi ddi → tôi đi    hoaf → hoà
              aa â  aw ă  ee ê  oo ô  ow ơ  uw ư  dd đ
              s f r x j = sắc huyền hỏi ngã nặng,  z removes the tone
              Esc right after a word flips it back to the raw letters (and again).

            Chinese (pinyin + tone number)
              ma3 → candidates 马 码 蚂 …, then 1–9 picks, Space takes the first
              ni3hao + Space → 你好    5 or 0 = neutral tone
              Enter keeps the letters, Esc cancels.

            English
              Anything else stays as typed: mp3, iphone15, class, I take the bus.

            Settings live in the input menu (top right): Traditional Chinese, tone style.
            """
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 13)
            label.isSelectable = true
            let box = NSView()
            label.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -20),
                label.topAnchor.constraint(equalTo: box.topAnchor, constant: 18),
                label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -18),
                label.widthAnchor.constraint(equalToConstant: 460),
            ])
            help = window("Emi Key Help", box)
        }
        bringFront(help!)
    }

    static func showAbout() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(string: "English, Vietnamese (Telex) and Chinese (pinyin) in one input method.\nOffline. Learned words in ~/Documents/Emi Key.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Emi Key", .credits: credits])
        for w in NSApp.windows where w.isVisible { w.level = .floating; w.orderFrontRegardless() }
    }
}

private final class SettingsView: NSView {
    private let trad = NSButton(checkboxWithTitle: "Traditional Chinese (繁體)", target: nil, action: nil)
    private let toneNew = NSButton(radioButtonWithTitle: "New style (hoà, thuý)", target: nil, action: nil)
    private let toneOld = NSButton(radioButtonWithTitle: "Old style (hòa, thúy)", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        trad.target = self; trad.action = #selector(changed(_:))
        toneNew.target = self; toneNew.action = #selector(changed(_:))
        toneOld.target = self; toneOld.action = #selector(changed(_:))
        let toneLabel = NSTextField(labelWithString: "Vietnamese tone placement")
        toneLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let chLabel = NSTextField(labelWithString: "Chinese")
        chLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let path = NSTextField(labelWithString: "Learned words: ~/Documents/Emi Key/learned.json")
        path.font = .systemFont(ofSize: 11); path.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [chLabel, trad, toneLabel, toneNew, toneOld, path])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(16, after: trad)
        stack.setCustomSpacing(16, after: toneOld)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 340),
        ])
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: AppState.settingsChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func refresh() {
        let s = AppState.shared
        trad.state = s.traditional ? .on : .off
        toneNew.state = s.toneStyle == .new ? .on : .off
        toneOld.state = s.toneStyle == .old ? .on : .off
    }

    @objc private func changed(_ sender: NSButton) {
        let s = AppState.shared
        if sender === trad { s.traditional = trad.state == .on }
        if sender === toneNew { s.toneStyle = .new }
        if sender === toneOld { s.toneStyle = .old }
    }
}
