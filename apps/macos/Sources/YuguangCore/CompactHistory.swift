import Foundation

/// A frozen reading viewport. Positive distances move down the newest-first list.
public struct CompactHistory: Sendable {
    public private(set) var position: Double = 0
    private var snapshot: [LiveEntry] = []
    public var offset: Int { Int(position / 32) }
    public var remainder: Double { position.truncatingRemainder(dividingBy: 32) }
    public var isReading: Bool { position > 0 }
    public init() {}
    public func visibleEntries(_ live: [LiveEntry]) -> [LiveEntry] {
        isReading ? Array(snapshot.dropFirst(offset)) : live
    }
    public func unreadCount(_ live: [LiveEntry]) -> Int {
        guard isReading else { return 0 }
        return Set(live.map(\.id)).subtracting(Set(snapshot.map(\.id))).count
    }
    public mutating func move(_ steps: Int, live: [LiveEntry]) {
        scroll(Double(max(-500, min(500, steps))) * 32, live: live)
    }
    /// Retains fractional points so trackpads scroll continuously rather than paging.
    public mutating func scroll(_ distance: Double, live: [LiveEntry], visibleRows: Int = 1) {
        guard distance.isFinite else { return }
        let rows = max(1, visibleRows)
        if !isReading {
            guard distance > 0, live.count > rows else { return }
            snapshot = live
        }
        position = min(max(0, position + distance), Double(max(0, snapshot.count - rows)) * 32)
        if position == 0 { reset() }
    }
    public mutating func reset() { position = 0; snapshot = [] }
}
