import Foundation

struct DoubleTapDetector {
    let interval: TimeInterval
    private var pending: TimeInterval?
    init(interval: TimeInterval = 0.45) { self.interval = interval }
    mutating func reset() { pending = nil }
    mutating func consume(clicks: Int, at time: TimeInterval) -> Bool {
        guard clicks > 0 else { return false }
        // A counter jump can combine two rapid presses into one advertisement.
        if clicks >= 2 { pending = nil; return true }
        if let previous = pending, time >= previous, time - previous <= interval {
            pending = nil
            return true
        }
        pending = time
        return false
    }
}
