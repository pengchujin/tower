import Foundation

/// QR Code (ISO/IEC 18004) encoder: byte mode, error-correction level M,
/// smallest version that fits, mask chosen by the standard penalty rules.
///
/// Tower used Core Image's `CIQRCodeGenerator`, but creating any `CIContext`
/// — even the software renderer — makes Metal open its shader archive
/// database and keep `com.apple.metal/archiveUsage.db/lock.mdb` locked for
/// the life of the process. The iPhone build on an Apple silicon Mac is
/// suspended shortly after its window closes, and RunningBoard kills a
/// process suspended holding that lock (0xdead10cc): every TestFlight Mac
/// crash through 1.0.30 (71). Encoding here and drawing with CoreGraphics
/// never touches Metal.
enum QRCodeEncoder {
    /// Row-major modules, `true` is dark. Nil when the payload exceeds
    /// version 40 at level M (2331 bytes).
    struct Symbol: Equatable {
        let size: Int
        let modules: [[Bool]]
    }

    static func encode(_ data: Data) -> Symbol? {
        let bytes = [UInt8](data)
        guard let version = (1...40).first(where: { fits(byteCount: bytes.count, version: $0) }) else { return nil }
        var builder = Builder(version: version)
        builder.drawFunctionPatterns()
        builder.drawCodewords(interleavedCodewords(bytes, version: version))
        builder.applyBestMask()
        return Symbol(size: builder.size, modules: builder.modules)
    }

    // MARK: Capacity

    /// Level M, indexed by version; index 0 unused.
    private static let eccCodewordsPerBlock = [
        -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
        26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    ]
    private static let errorCorrectionBlocks = [
        -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16,
        17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49,
    ]

    static func rawDataModules(version: Int) -> Int {
        var result = (16 * version + 128) * version + 64
        if version >= 2 {
            let alignmentCount = version / 7 + 2
            result -= (25 * alignmentCount - 10) * alignmentCount - 55
            if version >= 7 { result -= 36 }
        }
        return result
    }

    private static func dataCodewords(version: Int) -> Int {
        rawDataModules(version: version) / 8 - eccCodewordsPerBlock[version] * errorCorrectionBlocks[version]
    }

    private static func countBits(version: Int) -> Int { version <= 9 ? 8 : 16 }

    private static func fits(byteCount: Int, version: Int) -> Bool {
        let countBits = countBits(version: version)
        guard byteCount < 1 << countBits else { return false }
        return 4 + countBits + 8 * byteCount <= dataCodewords(version: version) * 8
    }

    // MARK: Data and error correction

    private static func interleavedCodewords(_ bytes: [UInt8], version: Int) -> [UInt8] {
        let capacityBits = dataCodewords(version: version) * 8
        var bits: [Bool] = []
        func append(_ value: Int, _ length: Int) {
            for i in stride(from: length - 1, through: 0, by: -1) { bits.append((value >> i) & 1 == 1) }
        }
        append(0b0100, 4)
        append(bytes.count, countBits(version: version))
        for byte in bytes { append(Int(byte), 8) }
        append(0, min(4, capacityBits - bits.count))
        append(0, (8 - bits.count % 8) % 8)
        var data: [UInt8] = stride(from: 0, to: bits.count, by: 8).map { start in
            (0..<8).reduce(UInt8(0)) { $0 << 1 | (bits[start + $1] ? 1 : 0) }
        }
        var pad: UInt8 = 0xEC
        while data.count < capacityBits / 8 {
            data.append(pad)
            pad ^= 0xEC ^ 0x11
        }

        let blockCount = errorCorrectionBlocks[version]
        let eccLength = eccCodewordsPerBlock[version]
        let rawCodewords = rawDataModules(version: version) / 8
        let shortBlockCount = blockCount - rawCodewords % blockCount
        let shortBlockLength = rawCodewords / blockCount
        let divisor = reedSolomonDivisor(degree: eccLength)
        var blocks: [[UInt8]] = []
        var offset = 0
        for index in 0..<blockCount {
            let length = shortBlockLength - eccLength + (index < shortBlockCount ? 0 : 1)
            var block = Array(data[offset..<offset + length])
            offset += length
            let ecc = reedSolomonRemainder(block, divisor: divisor)
            if index < shortBlockCount { block.append(0) }
            blocks.append(block + ecc)
        }
        var result: [UInt8] = []
        result.reserveCapacity(rawCodewords)
        for i in 0..<blocks[0].count {
            for (j, block) in blocks.enumerated() where i != shortBlockLength - eccLength || j >= shortBlockCount {
                result.append(block[i])
            }
        }
        return result
    }

    private static func multiply(_ x: UInt8, _ y: UInt8) -> UInt8 {
        var z = 0
        for i in stride(from: 7, through: 0, by: -1) {
            z = (z << 1) ^ ((z >> 7) * 0x11D)
            z ^= ((Int(y) >> i) & 1) * Int(x)
        }
        return UInt8(z & 0xFF)
    }

    private static func reedSolomonDivisor(degree: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: degree)
        result[degree - 1] = 1
        var root: UInt8 = 1
        for _ in 0..<degree {
            for j in 0..<degree {
                result[j] = multiply(result[j], root)
                if j + 1 < degree { result[j] ^= result[j + 1] }
            }
            root = multiply(root, 0x02)
        }
        return result
    }

    private static func reedSolomonRemainder(_ data: [UInt8], divisor: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: divisor.count)
        for byte in data {
            let factor = byte ^ result.removeFirst()
            result.append(0)
            for i in result.indices { result[i] ^= multiply(divisor[i], factor) }
        }
        return result
    }

    // MARK: Module placement

    private struct Builder {
        let version: Int
        let size: Int
        var modules: [[Bool]]
        var isFunction: [[Bool]]

        init(version: Int) {
            self.version = version
            size = version * 4 + 17
            modules = Array(repeating: Array(repeating: false, count: size), count: size)
            isFunction = modules
        }

        mutating func set(_ x: Int, _ y: Int, _ dark: Bool) {
            modules[y][x] = dark
            isFunction[y][x] = true
        }

        mutating func drawFunctionPatterns() {
            for i in 0..<size {
                set(6, i, i % 2 == 0)
                set(i, 6, i % 2 == 0)
            }
            for (x, y) in [(3, 3), (size - 4, 3), (3, size - 4)] {
                for dy in -4...4 {
                    for dx in -4...4 {
                        let xx = x + dx, yy = y + dy
                        guard (0..<size).contains(xx), (0..<size).contains(yy) else { continue }
                        let distance = max(abs(dx), abs(dy))
                        set(xx, yy, distance != 2 && distance != 4)
                    }
                }
            }
            let positions = alignmentPositions()
            let last = positions.count - 1
            for (i, x) in positions.enumerated() {
                for (j, y) in positions.enumerated() {
                    if (i == 0 && j == 0) || (i == 0 && j == last) || (i == last && j == 0) { continue }
                    for dy in -2...2 {
                        for dx in -2...2 { set(x + dx, y + dy, max(abs(dx), abs(dy)) != 1) }
                    }
                }
            }
            drawFormatBits(mask: 0)
            drawVersion()
        }

        func alignmentPositions() -> [Int] {
            guard version > 1 else { return [] }
            let count = version / 7 + 2
            let step = (version * 8 + count * 3 + 5) / (count * 4 - 4) * 2
            return [6] + (0..<(count - 1)).map { size - 7 - $0 * step }.reversed()
        }

        /// Level M encodes as 0b00 in the format information.
        mutating func drawFormatBits(mask: Int) {
            let data = mask
            var remainder = data
            for _ in 0..<10 { remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537) }
            let bits = (data << 10 | remainder) ^ 0x5412
            func bit(_ i: Int) -> Bool { (bits >> i) & 1 == 1 }
            for i in 0...5 { set(8, i, bit(i)) }
            set(8, 7, bit(6))
            set(8, 8, bit(7))
            set(7, 8, bit(8))
            for i in 9..<15 { set(14 - i, 8, bit(i)) }
            for i in 0..<8 { set(size - 1 - i, 8, bit(i)) }
            for i in 8..<15 { set(8, size - 15 + i, bit(i)) }
            set(8, size - 8, true)
        }

        mutating func drawVersion() {
            guard version >= 7 else { return }
            var remainder = version
            for _ in 0..<12 { remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25) }
            let bits = version << 12 | remainder
            for i in 0..<18 {
                let dark = (bits >> i) & 1 == 1
                let a = size - 11 + i % 3, b = i / 3
                set(a, b, dark)
                set(b, a, dark)
            }
        }

        mutating func drawCodewords(_ data: [UInt8]) {
            var index = 0
            var right = size - 1
            while right >= 1 {
                if right == 6 { right = 5 }
                for vertical in 0..<size {
                    for j in 0..<2 {
                        let x = right - j
                        let upward = (right + 1) & 2 == 0
                        let y = upward ? size - 1 - vertical : vertical
                        guard !isFunction[y][x], index < data.count * 8 else { continue }
                        modules[y][x] = (data[index >> 3] >> (7 - (index & 7))) & 1 == 1
                        index += 1
                    }
                }
                right -= 2
            }
        }

        mutating func applyMask(_ mask: Int) {
            for y in 0..<size {
                for x in 0..<size where !isFunction[y][x] {
                    let invert: Bool
                    switch mask {
                    case 0: invert = (x + y) % 2 == 0
                    case 1: invert = y % 2 == 0
                    case 2: invert = x % 3 == 0
                    case 3: invert = (x + y) % 3 == 0
                    case 4: invert = (x / 3 + y / 2) % 2 == 0
                    case 5: invert = x * y % 2 + x * y % 3 == 0
                    case 6: invert = (x * y % 2 + x * y % 3) % 2 == 0
                    default: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
                    }
                    if invert { modules[y][x].toggle() }
                }
            }
        }

        mutating func applyBestMask() {
            var best = 0
            var bestPenalty = Int.max
            for mask in 0..<8 {
                applyMask(mask)
                drawFormatBits(mask: mask)
                let score = penalty()
                if score < bestPenalty {
                    best = mask
                    bestPenalty = score
                }
                applyMask(mask)
            }
            applyMask(best)
            drawFormatBits(mask: best)
        }

        func penalty() -> Int {
            var result = 0
            for line in 0..<2 {
                for a in 0..<size {
                    var runColor = false
                    var runLength = 0
                    var history = [Int](repeating: 0, count: 7)
                    for b in 0..<size {
                        let dark = line == 0 ? modules[a][b] : modules[b][a]
                        if dark == runColor {
                            runLength += 1
                            if runLength == 5 { result += 3 } else if runLength > 5 { result += 1 }
                        } else {
                            addHistory(runLength, &history)
                            if !runColor { result += finderPatterns(history) * 40 }
                            runColor = dark
                            runLength = 1
                        }
                    }
                    if runColor {
                        addHistory(runLength, &history)
                        runLength = 0
                    }
                    addHistory(runLength + size, &history)
                    result += finderPatterns(history) * 40
                }
            }
            for y in 0..<(size - 1) {
                for x in 0..<(size - 1) {
                    let color = modules[y][x]
                    if color == modules[y][x + 1], color == modules[y + 1][x], color == modules[y + 1][x + 1] { result += 3 }
                }
            }
            let dark = modules.reduce(0) { $0 + $1.filter { $0 }.count }
            let total = size * size
            result += ((abs(dark * 20 - total * 10) + total - 1) / total - 1) * 10
            return result
        }

        func addHistory(_ length: Int, _ history: inout [Int]) {
            var length = length
            if history[0] == 0 { length += size }
            history.removeLast()
            history.insert(length, at: 0)
        }

        func finderPatterns(_ history: [Int]) -> Int {
            let n = history[1]
            let core = n > 0 && history[2] == n && history[3] == n * 3 && history[4] == n && history[5] == n
            return (core && history[0] >= n * 4 && history[6] >= n ? 1 : 0)
                + (core && history[6] >= n * 4 && history[0] >= n ? 1 : 0)
        }
    }
}
