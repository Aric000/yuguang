import AppKit
import Foundation

@main enum BrandBoard {
    static let orange = NSColor(calibratedRed: 0.95, green: 0.41, blue: 0.19, alpha: 1)
    static let ink = NSColor(calibratedWhite: 0.11, alpha: 1)
    static func text(_ string: String, at point: NSPoint, size: CGFloat, color: NSColor = ink, weight: NSFont.Weight = .regular) {
        (string as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
    static func mark(_ variant: Int, in rect: CGRect, inverse: Bool = false, mono: Bool = false) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); context.translateBy(x: rect.minX, y: rect.minY); context.scaleBy(x: rect.width / 100, y: rect.height / 100)
        context.setLineWidth(5); context.setLineCap(.round); context.setLineJoin(.round)
        for stroke in BrandGeometry.strokes(variant) {
            context.addPath(stroke.cgPath)
            context.setStrokeColor((stroke.accent && !mono ? orange : (inverse ? .white : ink)).cgColor)
            context.strokePath()
        }
        context.restoreGState()
    }
    static func save(_ image: NSImage, to path: String) throws {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: URL(fileURLWithPath: path))
    }
    static func main() throws {
        let directory = CommandLine.arguments[1]
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 1500, height: 1100))
        image.lockFocusFlipped(true)
        NSColor(calibratedWhite: 0.965, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1500, height: 1100).fill()
        text("余光", at: NSPoint(x: 64, y: 40), size: 38, weight: .semibold)
        text("四种看球的方式。", at: NSPoint(x: 64, y: 96), size: 19, color: .darkGray)
        text("品牌标志探索 / 可编辑矢量", at: NSPoint(x: 1110, y: 57), size: 16, color: .darkGray)
        for variant in 0..<4 {
            let x = CGFloat(variant % 2) * 702 + 48
            let y = CGFloat(variant / 2) * 432 + 160
            NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 684, height: 412), xRadius: 20, yRadius: 20).fill()
            text("\(["A", "B", "C", "D"][variant])  \(BrandGeometry.names[variant])", at: NSPoint(x: x + 28, y: y + 24), size: 23, weight: .medium)
            text(BrandGeometry.ideas[variant], at: NSPoint(x: x + 28, y: y + 66), size: 15, color: .darkGray)
            mark(variant, in: CGRect(x: x + 30, y: y + 114, width: 200, height: 200))
            ink.setFill(); NSBezierPath(roundedRect: NSRect(x: x + 278, y: y + 132, width: 156, height: 156), xRadius: 35, yRadius: 35).fill()
            mark(variant, in: CGRect(x: x + 294, y: y + 148, width: 124, height: 124), inverse: true)
            mark(variant, in: CGRect(x: x + 490, y: y + 176, width: 64, height: 64), mono: true)
            mark(variant, in: CGRect(x: x + 582, y: y + 194, width: 28, height: 28), mono: true)
            text("原色标志", at: NSPoint(x: x + 92, y: y + 340), size: 13, color: .darkGray)
            text("应用图标", at: NSPoint(x: x + 328, y: y + 340), size: 13, color: .darkGray)
            text("单色与小尺寸", at: NSPoint(x: x + 490, y: y + 340), size: 13, color: .darkGray)
            try BrandGeometry.svg(variant).write(toFile: "\(directory)/\(["A", "B", "C", "D"][variant])-\(BrandGeometry.names[variant]).svg", atomically: true, encoding: .utf8)
        }
        text("同一套矢量几何，可用于菜单栏、应用图标和窗口标题。", at: NSPoint(x: 64, y: 1042), size: 15, color: .darkGray)
        image.unlockFocus()
        try save(image, to: "\(directory)/logo-options.png")
    }
}
