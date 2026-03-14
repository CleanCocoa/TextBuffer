extension TextRope {
    internal struct Summary: Sendable, Equatable {
        var utf8: Int
        var utf16: Int
        var lines: Int

        static let zero = Summary(utf8: 0, utf16: 0, lines: 0)

        mutating func add(_ other: Summary) {
            utf8 += other.utf8
            utf16 += other.utf16
            lines += other.lines
        }

        mutating func subtract(_ other: Summary) {
            utf8 -= other.utf8
            utf16 -= other.utf16
            lines -= other.lines
        }

        static func of(_ string: String) -> Summary {
            var s = string
            var utf16 = 0
            var lines = 0
            s.withUTF8 { buffer in
                utf16 = string.utf16.count
                for byte in buffer {
                    if byte == UInt8(ascii: "\n") { lines += 1 }
                }
            }
            return Summary(utf8: string.utf8.count, utf16: utf16, lines: lines)
        }
    }
}
