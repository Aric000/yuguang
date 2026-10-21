import Foundation
import CoreGraphics

/// One vector source drives native UI, exported SVGs and the selection board.
enum BrandGeometry {
    enum Command {
        case move(CGFloat, CGFloat), line(CGFloat, CGFloat)
        case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        var svg: String {
            switch self {
            case .move(let x, let y): "M\(x) \(y)"
            case .line(let x, let y): "L\(x) \(y)"
            case .curve(let a, let b, let c, let d, let x, let y): "C\(a) \(b) \(c) \(d) \(x) \(y)"
            }
        }
    }
    struct Stroke {
        let accent: Bool
        let commands: [Command]
        var cgPath: CGPath {
            let p = CGMutablePath()
            for c in commands {
                switch c {
                case .move(let x, let y): p.move(to: CGPoint(x: x, y: y))
                case .line(let x, let y): p.addLine(to: CGPoint(x: x, y: y))
                case .curve(let a, let b, let c, let d, let x, let y):
                    p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: a, y: b), control2: CGPoint(x: c, y: d))
                }
            }
            return p
        }
    }
    static let names = ["空心入网", "余光之眼", "Y 形球网", "一线入框"]
    static let ideas = ["篮球落入篮筐，只留下轻盈的回响。", "余光是眼睛，也是球掠过篮筐的弧线。", "Yuguang 的 Y，恰好是一张收拢的球网。", "一条直播线，接住落进窗口的篮球。"]
    static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> [Command] {
        let k = r * 0.55228475
        return [.move(x + r, y), .curve(x + r, y + k, x + k, y + r, x, y + r),
                .curve(x - k, y + r, x - r, y + k, x - r, y),
                .curve(x - r, y - k, x - k, y - r, x, y - r),
                .curve(x + k, y - r, x + r, y - k, x + r, y)]
    }
    static func strokes(_ variant: Int) -> [Stroke] {
        switch variant {
        case 1:
            return [
                Stroke(accent: false, commands: [.move(14, 57), .curve(31, 33, 59, 33, 79, 47)]),
                Stroke(accent: false, commands: [.move(21, 66), .curve(39, 81, 66, 80, 85, 56)]),
                Stroke(accent: true, commands: circle(58, 53, 13)),
                Stroke(accent: false, commands: [.move(40, 62), .line(75, 62)])
            ]
        case 2:
            return [
                Stroke(accent: false, commands: [.move(22, 35), .line(50, 64), .line(78, 35)]),
                Stroke(accent: false, commands: [.move(50, 64), .line(50, 84)]),
                Stroke(accent: false, commands: [.move(31, 46), .line(69, 46)]),
                Stroke(accent: true, commands: circle(59, 21, 10))
            ]
        case 3:
            return [
                Stroke(accent: false, commands: [.move(20, 32), .line(20, 76), .line(80, 76), .line(80, 54)]),
                Stroke(accent: false, commands: [.move(34, 59), .line(66, 59)]),
                Stroke(accent: true, commands: circle(64, 30, 13)),
                Stroke(accent: true, commands: [.move(52, 30), .curve(60, 26, 68, 26, 76, 30), .move(62, 17), .curve(69, 24, 69, 36, 62, 43)])
            ]
        default:
            return [
                Stroke(accent: true, commands: circle(50, 31, 14)),
                Stroke(accent: true, commands: [.move(36, 31), .curve(43, 26, 57, 26, 64, 31), .move(48, 17), .curve(55, 25, 55, 37, 48, 45)]),
                Stroke(accent: false, commands: [.move(19, 56), .curve(32, 49, 68, 49, 81, 56), .curve(68, 65, 32, 65, 19, 56)]),
                Stroke(accent: false, commands: [.move(30, 63), .line(40, 82), .line(60, 82), .line(70, 63)]),
                Stroke(accent: false, commands: [.move(43, 65), .line(50, 81), .line(57, 65)])
            ]
        }
    }
    static func svg(_ variant: Int, ink: String = "#1A1D21") -> String {
        let paths = strokes(variant).map { stroke in
            "<path d=\"\(stroke.commands.map(\.svg).joined(separator: " "))\" stroke=\"\(stroke.accent ? "#F26830" : ink)\"/>"
        }.joined(separator: "\n")
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" fill="none" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" role="img" aria-label="余光 · \(names[variant])">
        \(paths)
        </svg>
        """
    }
}
