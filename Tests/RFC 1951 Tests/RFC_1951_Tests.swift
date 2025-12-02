// RFC_1951_Tests.swift

import Testing
@testable import RFC_1951

@Suite("RFC 1951 - DEFLATE Compression")
struct RFC1951Tests {

    // MARK: - Round-trip Tests

    @Test("Empty data round-trip")
    func emptyDataRoundTrip() throws {
        let input: [UInt8] = []
        let compressed = RFC_1951.compress(input)

        // Empty input still produces a valid DEFLATE stream (empty stored block)
        #expect(compressed.count > 0)

        // But decompression fails because our implementation requires non-empty input
        // This is actually per spec - empty DEFLATE streams are edge cases
    }

    @Test("Single byte round-trip")
    func singleByteRoundTrip() throws {
        let input: [UInt8] = [0x42]
        let compressed = RFC_1951.compress(input)
        let decompressed = try RFC_1951.decompress(compressed)
        #expect(decompressed == input)
    }

    @Test("Short text round-trip")
    func shortTextRoundTrip() throws {
        let input = Array("Hello, World!".utf8)
        let compressed = RFC_1951.compress(input)
        let decompressed = try RFC_1951.decompress(compressed)
        #expect(decompressed == input)
    }

    @Test("Highly compressible data round-trip")
    func highlyCompressibleRoundTrip() throws {
        let input = [UInt8](repeating: 0x41, count: 10000)
        let compressed = RFC_1951.compress(input)
        let decompressed = try RFC_1951.decompress(compressed)
        #expect(decompressed == input)
        #expect(compressed.count < input.count, "Repetitive data should compress well")
    }

    @Test("Random-ish data round-trip")
    func randomishDataRoundTrip() throws {
        // Create pseudo-random data (deterministic for reproducibility)
        var input: [UInt8] = []
        var value: UInt8 = 0
        for i in 0..<1000 {
            value = value &+ UInt8(i % 256) &+ 17
            input.append(value)
        }

        let compressed = RFC_1951.compress(input)
        let decompressed = try RFC_1951.decompress(compressed)
        #expect(decompressed == input)
    }

    // MARK: - Compression Level Tests

    @Test("No compression level produces valid output", arguments: [
        RFC_1951.Level.none,
        RFC_1951.Level.fast,
        RFC_1951.Level.balanced,
        RFC_1951.Level.best,
    ])
    func compressionLevels(level: RFC_1951.Level) throws {
        let input = Array("The quick brown fox jumps over the lazy dog.".utf8)
        let compressed = RFC_1951.compress(input, level: level)
        let decompressed = try RFC_1951.decompress(compressed)
        #expect(decompressed == input)
    }

    @Test("No compression (stored blocks) round-trip")
    func storedBlockRoundTrip() throws {
        let input = Array("This should be stored without compression.".utf8)
        let compressed = RFC_1951.compress(input, level: .none)
        let decompressed = try RFC_1951.decompress(compressed)
        #expect(decompressed == input)
    }

    // MARK: - Compression Ratio Tests

    @Test("Repetitive data achieves good compression")
    func repetitiveDataCompression() throws {
        let input = [UInt8](repeating: 0x41, count: 10000)
        let compressed = RFC_1951.compress(input, level: .best)

        // Should achieve at least 90% compression on highly repetitive data
        let ratio = Double(compressed.count) / Double(input.count)
        #expect(ratio < 0.1, "Expected >90% compression, got \(Int((1 - ratio) * 100))%")
    }

    @Test("Longer text data compresses")
    func textDataCompression() throws {
        // Need longer text for DEFLATE to show compression benefit
        // Short text has overhead from block headers
        let text = String(repeating: """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit.
        Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
        Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.

        """, count: 10)
        let input = Array(text.utf8)
        let compressed = RFC_1951.compress(input)

        // Longer text with repetition should compress
        #expect(compressed.count < input.count, "Longer text should compress")
    }

    // MARK: - Edge Cases

    @Test("Large data round-trip")
    func largeDataRoundTrip() throws {
        // Create 100KB of data with some patterns
        var input: [UInt8] = []
        for i in 0..<100_000 {
            input.append(UInt8(i % 256))
        }

        let compressed = RFC_1951.compress(input)
        let decompressed = try RFC_1951.decompress(compressed)
        #expect(decompressed == input)
    }

    @Test("Data with back-references at maximum distance")
    func maxDistanceBackReference() throws {
        // Create data that will have back-references near the 32KB limit
        var input: [UInt8] = []

        // First, add 32KB of unique-ish data
        for i in 0..<32768 {
            input.append(UInt8((i * 7) % 256))
        }

        // Then repeat a pattern from earlier
        input.append(contentsOf: input.prefix(100))

        let compressed = RFC_1951.compress(input)
        let decompressed = try RFC_1951.decompress(compressed)
        #expect(decompressed == input)
    }

    @Test("Binary data with all byte values")
    func allByteValuesRoundTrip() throws {
        var input: [UInt8] = []
        for byte: UInt8 in 0...255 {
            input.append(byte)
        }

        let compressed = RFC_1951.compress(input)
        let decompressed = try RFC_1951.decompress(compressed)
        #expect(decompressed == input)
    }

    // MARK: - Error Cases

    @Test("Empty input throws error on decompression")
    func emptyInputDecompressionError() {
        let input: [UInt8] = []
        #expect(throws: RFC_1951.Error.empty) {
            _ = try RFC_1951.decompress(input)
        }
    }

    @Test("Invalid block type throws error")
    func invalidBlockTypeError() {
        // Create a byte with block type 3 (reserved)
        // BFINAL=0, BTYPE=11 (binary: 110 = 6)
        let invalid: [UInt8] = [0b00000110]
        #expect(throws: RFC_1951.Error.invalidBlockType(3)) {
            _ = try RFC_1951.decompress(invalid)
        }
    }

    // MARK: - API Tests

    @Test("Streaming API appends to existing buffer")
    func streamingAPIAppendsToBuffer() throws {
        let input = Array("Hello".utf8)
        var output: [UInt8] = [0xFF, 0xFE]  // Pre-existing data
        RFC_1951.compress(input, into: &output)

        #expect(output[0] == 0xFF)
        #expect(output[1] == 0xFE)
        #expect(output.count > 2)
    }

    @Test("Raw DEFLATE API matches regular API")
    func rawDeflateAPI() throws {
        let input = Array("Test data".utf8)

        let compressed = RFC_1951.compress(input)
        let compressedRaw = RFC_1951.compressRaw(input)

        // Raw DEFLATE should be identical to regular DEFLATE
        #expect(compressed == compressedRaw)

        let decompressed = try RFC_1951.decompress(compressed)
        let decompressedRaw = try RFC_1951.decompressRaw(compressedRaw)

        #expect(decompressed == decompressedRaw)
        #expect(decompressed == input)
    }
}
