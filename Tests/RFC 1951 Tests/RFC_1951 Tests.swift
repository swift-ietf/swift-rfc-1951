import Byte
import Testing

@testable import RFC_1951

enum `RFC_1951 Tests` {}

extension `RFC_1951 Tests` {
    @Suite
    struct `RFC 1951 - DEFLATE Compression` {

        @Suite
        struct Unit {

            @Test
            func `Repetitive data achieves good compression`() throws {
                let input = [Byte](repeating: Byte(0x41), count: 1000)
                let compressed = RFC_1951.compress(input, level: .best)

                let ratio = Double(compressed.count) / Double(input.count)
                #expect(ratio < 0.1, "Expected >90% compression, got \(Int((1 - ratio) * 100))%")
            }

            @Test
            func `Longer text data compresses`() throws {

                let text = String(
                    repeating: """
                        Lorem ipsum dolor sit amet, consectetur adipiscing elit.
                        Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
                        Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.

                        """,
                    count: 10
                )
                let input = [Byte](utf8: text)
                let compressed = RFC_1951.compress(input)

                #expect(compressed.count < input.count, "Longer text should compress")
            }

            @Test
            func `Streaming API appends to existing buffer`() throws {
                let input = [Byte](utf8: "Hello")
                var output: [Byte] = [Byte(0xFF), Byte(0xFE)]
                RFC_1951.compress(input, into: &output)

                #expect(output[0] == Byte(0xFF))
                #expect(output[1] == Byte(0xFE))
                #expect(output.count > 2)
            }

            @Test
            func `Raw DEFLATE API matches regular API`() throws {
                let input = [Byte](utf8: "Test data")

                let compressed = RFC_1951.compress(input)
                let compressedRaw = RFC_1951.compressRaw(input)

                #expect(compressed == compressedRaw)

                let decompressed = try RFC_1951.decompress(compressed)
                let decompressedRaw = try RFC_1951.decompressRaw(compressedRaw)

                #expect(decompressed == decompressedRaw)
                #expect(decompressed == input)
            }
        }

        @Suite
        struct `Edge Case` {

            @Test(.timeLimit(.minutes(1)), arguments: [RFC_1951.Level.fast, .balanced, .best])
            func `a long run of one byte compresses in linear time and round-trips`(level: RFC_1951.Level) throws {
                let input = [Byte](repeating: Byte(0x2A), count: 4 << 20)
                let compressed = RFC_1951.compress(input, level: level)
                #expect(compressed.count < input.count / 100)
                #expect(try RFC_1951.decompress(compressed) == input)
            }

            @Test
            func `Back-reference into bytes before the call throws distanceTooFar`() throws {
                var writer = RFC_1951.BitWriter(into: [Byte]())
                RFC_1951.encodeFixedHuffmanBlock(
                    tokens: [.reference(length: 3, distance: 1)],
                    isFinal: true,
                    into: &writer
                )
                let stream = writer.finish()
                var output: [Byte] = [Byte(0xAB)]

                #expect(throws: RFC_1951.Error.distanceTooFar) {
                    try RFC_1951.decompress(stream, into: &output)
                }
                #expect(output == [Byte(0xAB)])
            }

            @Test
            func `Empty data round-trip`() throws {
                let input: [Byte] = []
                let compressed = RFC_1951.compress(input)

                #expect(!compressed.isEmpty)

            }

            @Test
            func `Large data round-trip`() throws {

                var input: [Byte] = []
                (0..<40_000).forEach { i in
                    input.append(Byte(UInt8(i % 256)))
                }

                let compressed = RFC_1951.compress(input)
                let decompressed = try RFC_1951.decompress(compressed)
                #expect(decompressed == input)
            }

            @Test
            func `Data with back-references at maximum distance`() throws {

                var input: [Byte] = []

                (0..<32768).forEach { i in
                    input.append(Byte(UInt8((i * 7) % 256)))
                }

                input.append(contentsOf: input.prefix(100))

                let compressed = RFC_1951.compress(input)
                let decompressed = try RFC_1951.decompress(compressed)
                #expect(decompressed == input)
            }

            @Test
            func `Binary data with all byte values`() throws {
                var input: [Byte] = []
                (UInt8(0)...255).forEach { byte in
                    input.append(Byte(byte))
                }

                let compressed = RFC_1951.compress(input)
                let decompressed = try RFC_1951.decompress(compressed)
                #expect(decompressed == input)
            }

            @Test
            func `Empty input throws error on decompression`() {
                let input: [Byte] = []
                #expect(throws: RFC_1951.Error.empty) {
                    _ = try RFC_1951.decompress(input)
                }
            }

            @Test
            func `Invalid block type throws error`() {

                let invalid: [Byte] = [Byte(0b00000110)]
                #expect(throws: RFC_1951.Error.invalidBlockType(Byte(3))) {
                    _ = try RFC_1951.decompress(invalid)
                }
            }
        }

        @Suite
        struct Integration {

            @Test
            func `Single byte round-trip`() throws {
                let input: [Byte] = [Byte(0x42)]
                let compressed = RFC_1951.compress(input)
                let decompressed = try RFC_1951.decompress(compressed)
                #expect(decompressed == input)
            }

            @Test
            func `Short text round-trip`() throws {
                let input = [Byte](utf8: "Hello, World!")
                let compressed = RFC_1951.compress(input)
                let decompressed = try RFC_1951.decompress(compressed)
                #expect(decompressed == input)
            }

            @Test
            func `Highly compressible data round-trip`() throws {
                let input = [Byte](repeating: Byte(0x41), count: 1000)
                let compressed = RFC_1951.compress(input)
                let decompressed = try RFC_1951.decompress(compressed)
                #expect(decompressed == input)
                #expect(compressed.count < input.count, "Repetitive data should compress well")
            }

            @Test
            func `Random-ish data round-trip`() throws {

                var input: [Byte] = []
                var value: UInt8 = 0
                (0..<1000).forEach { i in
                    value = value &+ UInt8(i % 256) &+ 17
                    input.append(Byte(value))
                }

                let compressed = RFC_1951.compress(input)
                let decompressed = try RFC_1951.decompress(compressed)
                #expect(decompressed == input)
            }

            @Test(
                arguments: [
                    RFC_1951.Level.none,
                    RFC_1951.Level.fast,
                    RFC_1951.Level.balanced,
                    RFC_1951.Level.best,
                ]
            )
            func `No compression level produces valid output`(level: RFC_1951.Level) throws {
                let input = [Byte](utf8: "The quick brown fox jumps over the lazy dog.")
                let compressed = RFC_1951.compress(input, level: level)
                let decompressed = try RFC_1951.decompress(compressed)
                #expect(decompressed == input)
            }

            @Test
            func `No compression (stored blocks) round-trip`() throws {
                let input = [Byte](utf8: "This should be stored without compression.")
                let compressed = RFC_1951.compress(input, level: .none)
                let decompressed = try RFC_1951.decompress(compressed)
                #expect(decompressed == input)
            }
        }
    }
}
