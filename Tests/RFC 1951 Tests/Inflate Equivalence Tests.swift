import Byte
import Testing

@testable import RFC_1951

enum `Inflate Equivalence Tests` {}

extension `Inflate Equivalence Tests` {
    @Suite
    struct `The table-driven inflate decodes as the plain bit-by-bit decoder does` {

        private static let prefix: [Byte] = [Byte(0xAB)]

        private static func fast<Input: Collection>(_ input: Input) -> [Byte] where Input.Element == Byte {
            var output = prefix
            do throws(RFC_1951.Error) {
                try RFC_1951.decompress(input, into: &output)
            } catch {
                output.append(contentsOf: [Byte](utf8: "error: \(error)"))
            }
            return output
        }

        private static func plain(_ input: [Byte]) -> [Byte] {
            var output = prefix
            do throws(RFC_1951.Error) {
                try Reference.decompress(input, into: &output)
            } catch {
                output.append(contentsOf: [Byte](utf8: "error: \(error)"))
            }
            return output
        }

        private static func expectSame(
            _ stream: [Byte],
            sourceLocation: SourceLocation = #_sourceLocation
        ) {
            let expected = plain(stream)
            #expect(fast(stream) == expected, "stream of \(stream.count) bytes", sourceLocation: sourceLocation)
        }

        private static var everyCodeTokens: [RFC_1951.LZ77Token] {
            var rng = Seeded(1951)
            var tokens: [RFC_1951.LZ77Token] = (0..<33_000).map { _ in .literal(Byte(UInt8.random(in: 0...255, using: &rng))) }
            for length in 3...258 {
                tokens.append(.reference(length: length, distance: 1 + length % 40))
            }
            for (code, base) in RFC_1951.distanceBase.enumerated() {
                let last = base + (1 << RFC_1951.distanceExtraBits[code]) - 1
                for distance in [base, last] {
                    tokens.append(.reference(length: 3, distance: distance))
                    tokens.append(.reference(length: 258, distance: distance))
                }
            }
            for distance in 1...16 {
                for length in 3...40 {
                    tokens.append(.reference(length: length, distance: distance))
                }
                tokens.append(.reference(length: 258, distance: distance))
            }
            tokens.append(.reference(length: 258, distance: 32768))
            return tokens
        }

        private static func randomCodeLengthLengths(using rng: inout Seeded) -> [Int] {
            Corpus.completeLengths(count: 19, maxLength: 7, using: &rng)
        }

        @Test
        func `every length and distance code, the maximum distance and overlapping matches decode alike`() {
            let tokens = Self.everyCodeTokens
            let fixed = Corpus.fixedStream(tokens)
            Self.expectSame(fixed)
            #expect(!String(decoding: Self.fast(fixed).map(\.underlying), as: UTF8.self).contains("error"))

            var rng = Seeded(7)
            var writer = Reference.BitWriter()
            Corpus.dynamicBlock(
                tokens,
                literalLengths: Corpus.completeLengths(count: 286, maxLength: 15, using: &rng),
                distanceLengths: Corpus.completeLengths(count: 30, maxLength: 15, using: &rng),
                codeLengthLengths: Self.randomCodeLengthLengths(using: &rng),
                useRuns: true,
                isFinal: true,
                into: &writer
            )
            let dynamic = writer.finish()
            Self.expectSame(dynamic)
            #expect(Self.fast(dynamic) == Self.fast(fixed))
        }

        @Test(arguments: 0..<8)
        func `seeded multi-block streams with random complete trees decode alike`(seed: Int) {
            var rng = Seeded(UInt64(seed) &+ 100)
            for _ in 0..<25 {
                var writer = Reference.BitWriter()
                let blocks = Int.random(in: 1...4, using: &rng)
                for block in 0..<blocks {
                    let isFinal = block == blocks - 1
                    let tokens = Corpus.tokens(
                        count: Int.random(in: 0...400, using: &rng),
                        referenceShare: Double.random(in: 0...0.6, using: &rng),
                        using: &rng
                    )
                    switch Int.random(in: 0...2, using: &rng) {
                    case 0:
                        let data = (0..<Int.random(in: 0...300, using: &rng)).map { _ in
                            Byte(UInt8.random(in: 0...255, using: &rng))
                        }
                        writer.writeBit(isFinal ? 1 : 0)
                        writer.writeBits(0, count: 2)
                        writer.alignToByte()
                        let len = UInt16(data.count)
                        writer.writeBits(UInt32(len), count: 16)
                        writer.writeBits(UInt32(~len), count: 16)
                        writer.writeBytes(data)

                    case 1:
                        Reference.encodeFixedHuffmanBlock(tokens, isFinal: isFinal, into: &writer)

                    default:
                        Corpus.dynamicBlock(
                            tokens,
                            literalLengths: Corpus.completeLengths(
                                count: Int.random(in: 286...288, using: &rng),
                                maxLength: Int.random(in: 9...15, using: &rng),
                                using: &rng
                            ),
                            distanceLengths: Corpus.completeLengths(
                                count: Int.random(in: 30...32, using: &rng),
                                maxLength: Int.random(in: 5...15, using: &rng),
                                using: &rng
                            ),
                            codeLengthLengths: Self.randomCodeLengthLengths(using: &rng),
                            useRuns: Bool.random(using: &rng),
                            isFinal: isFinal,
                            into: &writer
                        )
                    }
                }
                Self.expectSame(writer.finish())
            }
        }

        @Test
        func `degenerate dynamic trees decode alike`() {
            var rng = Seeded(31)
            let literalOnly = Corpus.tokens(count: 300, referenceShare: 0, using: &rng)
            let distanceOne: [RFC_1951.LZ77Token] = [.literal(Byte(7))] + (3...258).map { .reference(length: $0, distance: 1) }

            func stream(_ tokens: [RFC_1951.LZ77Token], literal: [Int], distance: [Int]) -> [Byte] {
                var writer = Reference.BitWriter()
                Corpus.dynamicBlock(
                    tokens,
                    literalLengths: literal,
                    distanceLengths: distance,
                    codeLengthLengths: Self.randomCodeLengthLengths(using: &rng),
                    useRuns: true,
                    isFinal: true,
                    into: &writer
                )
                return writer.finish() + [Byte(0xFF), Byte(0x00)]
            }

            let complete = Corpus.completeLengths(count: 286, maxLength: 15, using: &rng)
            Self.expectSame(stream(literalOnly, literal: complete, distance: [Int](repeating: 0, count: 30)))
            Self.expectSame(stream(distanceOne, literal: complete, distance: [1] + [Int](repeating: 0, count: 29)))
            Self.expectSame(stream(distanceOne, literal: complete, distance: [Int](repeating: 0, count: 29) + [1]))

            var single = [Int](repeating: 0, count: 257)
            single[256] = 1
            Self.expectSame(stream([], literal: single, distance: [0]))
            single[65] = 1
            Self.expectSame(stream([.literal(Byte(65))], literal: single, distance: [0]))
        }

        @Test(arguments: 0..<4)
        func `incomplete and oversubscribed trees decode alike`(seed: Int) {
            var rng = Seeded(UInt64(seed) &+ 500)
            for _ in 0..<100 {
                var writer = Reference.BitWriter()
                let oversubscribed = Bool.random(using: &rng)
                let literal = (0..<Int.random(in: 257...288, using: &rng)).map { _ in
                    oversubscribed ? Int.random(in: 0...15, using: &rng) : (Bool.random(using: &rng) ? 0 : 9)
                }
                let distance = (0..<Int.random(in: 1...32, using: &rng)).map { _ in
                    Int.random(in: 0...(oversubscribed ? 15 : 0), using: &rng) | (oversubscribed ? 0 : 5)
                }
                Corpus.writeDynamicHeader(
                    literalLengths: literal,
                    distanceLengths: distance,
                    codeLengthLengths: Self.randomCodeLengthLengths(using: &rng),
                    useRuns: Bool.random(using: &rng),
                    isFinal: true,
                    into: &writer
                )
                for _ in 0..<Int.random(in: 0...2000, using: &rng) {
                    writer.writeBit(UInt8.random(in: 0...1, using: &rng))
                }
                Self.expectSame(writer.finish())
            }
        }

        @Test
        func `every truncation of a stream fails or succeeds alike`() {
            var rng = Seeded(77)
            let tokens = Corpus.tokens(count: 300, referenceShare: 0.3, using: &rng)
            var dynamic = Reference.BitWriter()
            Corpus.dynamicBlock(
                tokens,
                literalLengths: Corpus.completeLengths(count: 286, maxLength: 15, using: &rng),
                distanceLengths: Corpus.completeLengths(count: 30, maxLength: 15, using: &rng),
                codeLengthLengths: Self.randomCodeLengthLengths(using: &rng),
                useRuns: true,
                isFinal: true,
                into: &dynamic
            )
            let streams = [
                Corpus.fixedStream(tokens),
                dynamic.finish(),
                RFC_1951.compress(Corpus.text(3000), level: .none),
                RFC_1951.compress(Corpus.text(3000)),
            ]
            for stream in streams {
                for count in 0...stream.count {
                    Self.expectSame(Array(stream.prefix(count)))
                }
            }
        }

        @Test(arguments: 0..<4)
        func `corrupted streams fail or succeed alike`(seed: Int) {
            var rng = Seeded(UInt64(seed) &+ 900)
            let sources = [
                Corpus.fixedStream(Self.everyCodeTokens.suffix(2000)),
                RFC_1951.compress(Corpus.text(4000)),
                RFC_1951.compress(Corpus.random(500)),
            ]
            for _ in 0..<300 {
                var stream = sources.randomElement(using: &rng)!
                for _ in 0..<Int.random(in: 1...4, using: &rng) {
                    let index = Int.random(in: stream.indices, using: &rng)
                    stream[index] = Byte(stream[index].underlying ^ (1 << UInt8.random(in: 0...7, using: &rng)))
                }
                Self.expectSame(stream)
            }
        }

        @Test(arguments: 0..<4)
        func `random bytes fail or succeed alike`(seed: Int) {
            var rng = Seeded(UInt64(seed) &+ 1300)
            for _ in 0..<1000 {
                var stream = (0..<Int.random(in: 1...96, using: &rng)).map { _ in
                    Byte(UInt8.random(in: 0...255, using: &rng))
                }
                stream[0] = Byte(stream[0].underlying & 0b1111_1001 | UInt8(seed % 4) << 1)
                Self.expectSame(stream)
            }
        }

        @Test
        func `empty input throws empty`() {
            Self.expectSame([])
        }

        @Test(arguments: [RFC_1951.Level.none, .fast, .balanced, .best])
        func `the package's own deflate round-trips and decodes alike`(level: RFC_1951.Level) throws {
            for input in [Corpus.image(100_000), Corpus.runs(100_000), Corpus.random(70_000), Corpus.text(100_000), []] {
                let stream = RFC_1951.compress(input, level: level)
                #expect(try RFC_1951.decompress(stream) == input)
                Self.expectSame(stream)
            }
        }

        @Test
        func `sliced and non-contiguous input decode as an array does`() throws {
            let input = Corpus.text(20_000)
            let stream = RFC_1951.compress(input)
            let padded = [Byte(1), Byte(2)] + stream
            #expect(try RFC_1951.decompress(padded.dropFirst(2)) == input)
            #expect(try RFC_1951.decompress(stream.lazy.map { $0 }) == input)
            #expect(Self.fast(stream.lazy.map { $0 }.dropLast(5)) == Self.plain(Array(stream.dropLast(5))))
        }
    }
}
