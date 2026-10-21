import AppKit
import Foundation

@main enum MakeIcon {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 64, 128, 256, 512, 1024] {
            let image = NSImage(size: NSSize(width: size, height: size))
            image.lockFocusFlipped(true)
            let s = CGFloat(size)
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: s * 0.07, y: s * 0.07, width: s * 0.86, height: s * 0.86), xRadius: s * 0.20, yRadius: s * 0.20).fill()
            if let context = NSGraphicsContext.current?.cgContext {
                context.translateBy(x: s * 0.10, y: s * 0.06)
                context.scaleBy(x: s * 0.008, y: s * 0.008)
                context.setLineWidth(5); context.setLineCap(.round); context.setLineJoin(.round)
                for stroke in BrandGeometry.strokes(1) {
                    context.addPath(stroke.cgPath)
                    context.setStrokeColor((stroke.accent ? NSColor(calibratedRed: 0.95, green: 0.41, blue: 0.19, alpha: 1) : NSColor.white).cgColor)
                    context.strokePath()
                }
            }
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { continue }
            if size <= 512 { try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size).png")) }
            if size >= 32 { try data.write(to: directory.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png")) }
        }
    }
}
