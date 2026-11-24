import Cocoa

/// Borderless, non-activating floating bar: "1 马  2 码  3 蚂", first one highlighted, clickable.
final class CandidateWindow {
    static let shared = CandidateWindow()
    var onPick: ((Int) -> Void)?

    private let panel: NSPanel
    private let effect = NSVisualEffectView()
    private let stack = NSStackView()
    private let pad: CGFloat = 4

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 30),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: pad, left: pad, bottom: pad, right: pad)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
        ])
        panel.contentView = effect
    }

    func show(_ candidates: [String], under caret: NSRect) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, text) in candidates.prefix(9).enumerated() {
            let cell = CandidateCell(index: i, text: text, highlighted: i == 0)
            cell.onClick = { [weak self] in self?.onPick?(i) }
            stack.addArrangedSubview(cell)
        }
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        var origin = NSPoint(x: caret.minX, y: caret.minY - size.height - 4)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: caret.midX, y: caret.midY)) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            if origin.y < vf.minY { origin.y = caret.maxY + 4 }                // no room below: go above
            origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

private final class CandidateCell: NSView {
    var onClick: (() -> Void)?
    private let highlighted: Bool

    init(index: Int, text: String, highlighted: Bool) {
        self.highlighted = highlighted
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        let num = NSTextField(labelWithString: "\(index + 1)")
        num.font = .systemFont(ofSize: 11, weight: .medium)
        num.textColor = highlighted ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
        let word = NSTextField(labelWithString: text)
        word.font = .systemFont(ofSize: 15)
        word.textColor = highlighted ? .white : .labelColor
        let row = NSStackView(views: [num, word])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 4
        row.edgeInsets = NSEdgeInsets(top: 3, left: 7, bottom: 3, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = highlighted ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
    }
    override var wantsUpdateLayer: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
