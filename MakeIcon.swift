import AppKit
import Foundation
let folder = URL(fileURLWithPath: "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 195, yRadius: 195)
    NSGradient(colors: [NSColor(calibratedRed: 0.28, green: 0.22, blue: 0.8, alpha: 1), NSColor(calibratedRed: 0.55, green: 0.4, blue: 0.98, alpha: 1)])!.draw(in: background, angle: 45)
    for (offset, alpha) in [(CGFloat(-64),CGFloat(0.25)),(CGFloat(0),CGFloat(0.5)),(CGFloat(64),CGFloat(1))] {
        let plate = NSBezierPath(roundedRect: NSRect(x: 262, y: 278 + offset, width: 500, height: 320), xRadius: 54, yRadius: 54)
        NSColor.white.withAlphaComponent(alpha).setFill(); plate.fill()
    }
    NSColor(calibratedRed: 0.39, green: 0.3, blue: 0.85, alpha: 1).setStroke()
    let line = NSBezierPath(); line.lineWidth = 28; line.lineCapStyle = .round
    line.move(to: NSPoint(x: 512,y: 576)); line.line(to: NSPoint(x: 512,y: 420))
    line.move(to: NSPoint(x: 455,y: 477)); line.line(to: NSPoint(x: 512,y: 420)); line.line(to: NSPoint(x: 569,y: 477)); line.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: folder.appendingPathComponent(name)) }
}

var chunks = Data()
func lengthBytes(_ value: Int) -> Data { var number = UInt32(value).bigEndian; return withUnsafeBytes(of: &number) { Data($0) } }
for (kind, filename) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let image = try Data(contentsOf: folder.appendingPathComponent(filename))
    chunks.append(Data(kind.utf8)); chunks.append(lengthBytes(image.count + 8)); chunks.append(image)
}
var container = Data("icns".utf8); container.append(lengthBytes(chunks.count + 8)); container.append(chunks)
try container.write(to: URL(fileURLWithPath: "build/AppIcon.icns"))
