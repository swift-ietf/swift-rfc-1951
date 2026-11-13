import Byte
import Testing

@testable import RFC_1951

enum `Throughput Tests` {}

extension `Throughput Tests` {
    @Suite(.serialized)
    struct `Throughput on 8 MB inputs, printed and not asserted` {

        private static func seconds(_ body: () throws -> Void) rethrows -> Double {
            let clock = ContinuousClock()
            var best = Double.infinity
            for _ in 0..<3 {
                let elapsed = try clock.measure(body)
                best = min(best, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            }
            return best
        }

        @Test(arguments: ["image", "runs", "random", "text"])
        func `inflate and deflate throughput`(name: String) throws {
            let count = 8 << 20
            let input: [Byte]
            switch name {
            case "image": input = Corpus.image(count)
            case "runs": input = Corpus.runs(count)
            case "random": input = Corpus.random(count)
            default: input = Corpus.text(count)
            }
            var stream: [Byte] = []
            let deflate = Self.seconds { stream = RFC_1951.compress(input) }
            var output: [Byte] = []
            let inflate = try Self.seconds { output = try RFC_1951.decompress(stream) }
            #expect(output == input)
            let megabytes = Double(count) / 1e6
            print(
                "\(name): deflate \(Int(megabytes / deflate)) MB/s of input, inflate \(Int(megabytes / inflate)) MB/s of output, \(stream.count) bytes deflated"
            )
        }
    }
}
