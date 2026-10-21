import AppKit

@MainActor enum BrandRenderer {
    static func menuIcon() -> NSImage {
        let size = NSSize(width: 21, height: 17)
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        if let context = NSGraphicsContext.current?.cgContext {
            let paths = BrandGeometry.strokes(1).map(\.cgPath)
            let bounds = paths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
            let scale = min((size.width - 3) / bounds.width, (size.height - 3) / bounds.height)
            context.translateBy(x: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(5); context.setLineCap(.round); context.setLineJoin(.round)
            for path in paths { context.addPath(path); context.strokePath() }
        }
        image.unlockFocus()
        image.isTemplate = true // System handles light / dark menu bars and selected menus.
        image.accessibilityDescription = "余光之眼"
        return image
    }
}
