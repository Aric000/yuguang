import SwiftUI

struct BrandMark: View {
    var variant = 1
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let transform = CGAffineTransform(scaleX: side / 100, y: side / 100)
                .translatedBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            for stroke in BrandGeometry.strokes(variant) {
                let color: Color = stroke.accent ? Color(red: 0.95, green: 0.41, blue: 0.19) : (scheme == .dark ? .white : Color(white: 0.12))
                context.stroke(Path(stroke.cgPath).applying(transform), with: .color(color), style: StrokeStyle(lineWidth: side * 0.055, lineCap: .round, lineJoin: .round))
            }
        }.accessibilityLabel("余光 · " + BrandGeometry.names[variant])
    }
}
