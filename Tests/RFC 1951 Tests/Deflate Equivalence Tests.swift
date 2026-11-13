import Byte
import Testing

@testable import RFC_1951

enum `Deflate Equivalence Tests` {}

extension `Deflate Equivalence Tests` {
    @Suite
    struct `The word-at-a-time deflate writes what the plain bit-by-bit deflate writes` {

        @Test
        func `length and distance codes match the linear search for every value`() {
            (0...300).forEach { length in
                #expect(RFC_1951.encodeLengthCode(length) == Reference.lengthCode(length))
            }
            (-2...33_000).forEach { distance in
                #expect(RFC_1951.encodeDistanceCode(distance) == Reference.distanceCode(distance))
            }
        }

        @Test(arguments: 0..<4)
        func `the bit writer writes what the plain bit writer writes`(seed: Int) {
            var rng = Seeded(UInt64(seed) &+ 40)
            for _ in 0..<200 {
                var fast = RFC_1951.BitWriter(into: [])
                var plain = Reference.BitWriter()
                for _ in 0..<Int.random(in: 0...300, using: &rng) {
                    let value = UInt32.random(in: 0...UInt32.max, using: &rng)
                    let count = Int.random(in: 0...16, using: &rng)
                    switch Int.random(in: 0...9, using: &rng) {
                    case 0:
                        fast.writeBit(UInt8(value & 1))
                        plain.writeBit(UInt8(value & 1))
                    case 1...4:
                        fast.writeBits(value, count: count)
                        plain.writeBits(value, count: count)
                    case 5...7:
                        fast.writeBitsReversed(value, count: count)
                        plain.writeBitsReversed(value, count: count)
                    case 8:
                        fast.alignToByte()
                        plain.alignToByte()
                    default:
                        let bytes = (0..<count).map { _ in Byte(UInt8.random(in: 0...255, using: &rng)) }
                        fast.writeBytes(bytes)
                        plain.writeBytes(bytes)
                    }
                }
                #expect(fast.finish() == plain.finish())
            }
        }

        @Test(arguments: [RFC_1951.Level.none, .fast, .balanced, .best])
        func `compress writes the bytes the plain compressor writes`(level: RFC_1951.Level) {
            let inputs = [
                Corpus.image(150_000), Corpus.runs(150_000), Corpus.random(80_000), Corpus.text(150_000),
                Corpus.text(7), [], [Byte(0)],
            ]
            for input in inputs {
                #expect(RFC_1951.compress(input, level: level) == Reference.compress(input, level: level))
            }
        }

        @Test
        func `compress into a buffer keeps its bytes and appends the stream`() {
            let input = Corpus.text(5000)
            var output: [Byte] = [Byte(9), Byte(8)]
            RFC_1951.compress(input, into: &output)
            #expect(output == [Byte(9), Byte(8)] + Reference.compress(input, level: .balanced))
        }
    }
}
