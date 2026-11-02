import AppKit
import Foundation

let destination = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let fm = FileManager.default
try fm.createDirectory(atPath: destination + "/AppIcon.iconset", withIntermediateDirectories: true)
func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.10); shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width: 0, height: -5)
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 205, yRadius: 205).fill()
    NSShadow().set()
    NSColor(calibratedRed: 0.14, green: 0.20, blue: 0.21, alpha: 1).setStroke()
    let body = NSBezierPath(); body.lineWidth = 22; body.lineCapStyle = .round; body.lineJoinStyle = .round
    body.move(to: NSPoint(x: 343, y: 599)); body.line(to: NSPoint(x: 365, y: 318))
    body.curve(to: NSPoint(x: 406, y: 277), controlPoint1: NSPoint(x: 368, y: 292), controlPoint2: NSPoint(x: 380, y: 277))
    body.line(to: NSPoint(x: 618, y: 277)); body.curve(to: NSPoint(x: 659, y: 318), controlPoint1: NSPoint(x: 644, y: 277), controlPoint2: NSPoint(x: 656, y: 292))
    body.line(to: NSPoint(x: 681, y: 599)); body.stroke()
    let lid = NSBezierPath(); lid.lineWidth = 22; lid.lineCapStyle = .round
    lid.move(to: NSPoint(x: 310, y: 651)); lid.line(to: NSPoint(x: 714, y: 651)); lid.stroke()
    let handle = NSBezierPath(); handle.lineWidth = 22; handle.lineCapStyle = .round; handle.lineJoinStyle = .round
    handle.move(to: NSPoint(x: 440, y: 651)); handle.line(to: NSPoint(x: 440, y: 704)); handle.curve(to: NSPoint(x: 464, y: 728), controlPoint1: NSPoint(x: 440, y: 720), controlPoint2: NSPoint(x: 448, y: 728)); handle.line(to: NSPoint(x: 560, y: 728)); handle.curve(to: NSPoint(x: 584, y: 704), controlPoint1: NSPoint(x: 576, y: 728), controlPoint2: NSPoint(x: 584, y: 720)); handle.line(to: NSPoint(x: 584, y: 651)); handle.stroke()
    for x in [466.0, 558.0] { let line = NSBezierPath(); line.lineWidth = 18; line.lineCapStyle = .round; line.move(to: NSPoint(x: x, y: 551)); line.line(to: NSPoint(x: x, y: 378)); line.stroke() }
    NSGraphicsContext.restoreGraphicsState(); return rep
}
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let suffix = factor == 2 ? "@2x" : ""
        let data = drawIcon(size: size * factor).representation(using: .png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: destination + "/AppIcon.iconset/icon_\(size)x\(size)\(suffix).png"))
    }
}
try drawIcon(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination + "/AppIcon.png"))
