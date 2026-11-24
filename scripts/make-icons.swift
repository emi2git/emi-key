// Generates the C2 "brush strokes" icons.
//   swift scripts/make-icons.swift
// Writes Resources/AppIcon.icns (via iconutil) and Resources/MenuIconTemplate.tiff (16 px @1x + 32 px @2x, black template).
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let res = root.appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)

// The three strokes in a 24×24 box, y down (SVG coordinates).
enum Stroke: CaseIterable { case left, centre, right }
func strokePath(_ s: Stroke) -> CGPath {
    let p = CGMutablePath()
    switch s {
    case .left:   // M12 22C9.5 16 6.5 10 3 5C7.5 8 10.8 13.5 12 22Z
        p.move(to: .init(x: 12, y: 22))
        p.addCurve(to: .init(x: 3, y: 5), control1: .init(x: 9.5, y: 16), control2: .init(x: 6.5, y: 10))
        p.addCurve(to: .init(x: 12, y: 22), control1: .init(x: 7.5, y: 8), control2: .init(x: 10.8, y: 13.5))
    case .centre: // M12 22C10.6 15 10.6 8 12 2C13.4 8 13.4 15 12 22Z
        p.move(to: .init(x: 12, y: 22))
        p.addCurve(to: .init(x: 12, y: 2), control1: .init(x: 10.6, y: 15), control2: .init(x: 10.6, y: 8))
        p.addCurve(to: .init(x: 12, y: 22), control1: .init(x: 13.4, y: 8), control2: .init(x: 13.4, y: 15))
    case .right:  // M12 22C14.5 16 17.5 10 21 5C16.5 8 13.2 13.5 12 22Z
        p.move(to: .init(x: 12, y: 22))
        p.addCurve(to: .init(x: 21, y: 5), control1: .init(x: 14.5, y: 16), control2: .init(x: 17.5, y: 10))
        p.addCurve(to: .init(x: 12, y: 22), control1: .init(x: 16.5, y: 8), control2: .init(x: 13.2, y: 13.5))
    }
    p.closeSubpath()
    return p
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func bitmap(_ px: Int, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
    let c = g.cgContext
    c.clear(CGRect(x: 0, y: 0, width: px, height: px))
    draw(c)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Draws the strokes so the 24-unit box maps onto `box` (CG coordinates, y up).
func drawStrokes(_ c: CGContext, in box: CGRect, colors: [CGColor]) {
    c.saveGState()
    c.translateBy(x: box.minX, y: box.maxY)
    c.scaleBy(x: box.width / 24, y: -box.height / 24)
    for (s, col) in zip(Stroke.allCases, colors) {
        c.addPath(strokePath(s)); c.setFillColor(col); c.fillPath()
    }
    c.restoreGState()
}

// MARK: app icon
func appIcon(_ px: Int) -> NSBitmapImageRep {
    bitmap(px) { c in
        let s = CGFloat(px)
        let body = CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
        let squircle = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)
        // soft drop shadow like system icons
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.025, color: CGColor(gray: 0, alpha: 0.35))
        c.addPath(squircle); c.setFillColor(rgb(0x151e29)); c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(squircle); c.clip()
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0x263445), rgb(0x151e29)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(grad, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
        c.restoreGState()
        let inset = body.width * 0.12
        drawStrokes(c, in: body.insetBy(dx: inset, dy: inset), colors: [rgb(0x3b82d6), rgb(0xd9402b), rgb(0xe9a91c)])
    }
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! appIcon(base * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", res.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
precondition(p.terminationStatus == 0, "iconutil failed")

// MARK: menu-bar template icon (black on transparent)
func menuIcon(_ px: Int) -> NSBitmapImageRep {
    let rep = bitmap(px) { c in
        let s = CGFloat(px)
        drawStrokes(c, in: CGRect(x: 0, y: 0, width: s, height: s), colors: Array(repeating: CGColor(gray: 0, alpha: 1), count: 3))
    }
    rep.size = NSSize(width: 16, height: 16)   // points: 16 px = @1x, 32 px = @2x
    return rep
}
let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [menuIcon(16), menuIcon(32)], using: .lzw, factor: 0)!
try! tiff.write(to: res.appendingPathComponent("MenuIconTemplate.tiff"))
try! menuIcon(16).representation(using: .png, properties: [:])!.write(to: res.appendingPathComponent("MenuIconTemplate.png"))
try! menuIcon(32).representation(using: .png, properties: [:])!.write(to: res.appendingPathComponent("MenuIconTemplate@2x.png"))
print("icons written to \(res.path)")
