import AppKit
import SwiftUI
import YuguangCore

struct TeamIdentity: Decodable {
    let name: String
    let logo: String
    let dayColor: String?
    let nightColor: String?
}

@MainActor enum TeamAssets {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Yuguang_Yuguang.bundle"), let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
    static let catalog: [String: TeamIdentity] = {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "Teams"),
              let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode([String: TeamIdentity].self, from: data) else { return [:] }
        return catalog
    }()
    private static let images = NSCache<NSString, NSImage>()
    static func image(_ name: String) -> NSImage? {
        if let image = images.object(forKey: name as NSString) { return image }
        guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Teams"), let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: name as NSString); return image
    }
    static func color(name: String, hex: String? = nil, dark: Bool = false) -> Color {
        let raw = hex ?? (dark ? catalog[name]?.nightColor : catalog[name]?.dayColor) ?? "647481"
        let string = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return Color.gray }
        var r = Double((value >> 16) & 255) / 255
        var g = Double((value >> 8) & 255) / 255
        var b = Double(value & 255) / 255
        // Team hues remain recognisable, with enough lightness on the charcoal theme.
        if dark && max(r, g, b) < 0.65 { r = r * 0.60 + 0.40; g = g * 0.60 + 0.40; b = b * 0.60 + 0.40 }
        return Color(red: r, green: g, blue: b)
    }
}

struct TeamBadge: View {
    let name: String
    var remoteURL: String? = nil
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let image = TeamAssets.image(name) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let url = remoteURL.flatMap({ URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) }) {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { fallback }
            } else { fallback }
        }.frame(width: size, height: size).accessibilityLabel(name + "队徽")
    }
    private var fallback: some View {
        Text(String(name.prefix(1))).font(.system(size: size * 0.40, weight: .semibold)).foregroundStyle(.secondary)
    }
}
