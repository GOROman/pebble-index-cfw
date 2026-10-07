import Foundation

struct ClickCounter {
    private(set) var previous: UInt8?

    // Each advertising burst repeats the same counter. A reset to zero is not a click.
    mutating func consume(_ value: UInt8) -> Int {
        defer { previous = value }
        guard let old = previous else { return value == 0 ? 0 : 1 }
        let delta = (Int(value) - Int(old) + 256) % 256
        if value < old && delta > 8 { return 0 }
        return delta
    }

    static func parse(_ data: Data) -> UInt8? {
        let bytes = Array(data)
        guard bytes.count >= 3, bytes[0] == 0xff, bytes[1] == 0xff else { return nil }
        return bytes[2]
    }
}
