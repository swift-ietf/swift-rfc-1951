import Byte

@testable import RFC_1951

enum Corpus {}

extension Corpus {

    static func image(_ count: Int, seed: UInt64 = 1) -> [Byte] {
        var rng = Seeded(seed)
        let width = 2048
        return (0..<count).map { i in
            let x = i % width
            let y = i / width
            let base = (y * 255 / max(count / width, 1) + x * 255 / width) / 2 + 64
            return Byte(UInt8(truncatingIfNeeded: base + Int.random(in: -3...3, using: &rng)))
        }
    }

    static func runs(_ count: Int, seed: UInt64 = 2) -> [Byte] {
        var rng = Seeded(seed)
        var bytes: [Byte] = []
        bytes.reserveCapacity(count + 4000)
        while bytes.count < count {
            let byte = Byte(UInt8.random(in: 0...255, using: &rng))
            bytes.append(contentsOf: repeatElement(byte, count: Int.random(in: 50...4000, using: &rng)))
        }
        return Array(bytes.prefix(count))
    }

    static func random(_ count: Int, seed: UInt64 = 3) -> [Byte] {
        var rng = Seeded(seed)
        return (0..<count).map { _ in Byte(UInt8.random(in: 0...255, using: &rng)) }
    }

    static func text(_ count: Int, seed: UInt64 = 4) -> [Byte] {
        var rng = Seeded(seed)
        let words = Array(
            "the of and to in is was that for it with as his on be at by had this not are but from or have an they which one you were her all she there would their we him been has when who will more no if out so said what up its about into than them can only other new some could time these two may then"
                .split(separator: " ")
        )
        var bytes: [Byte] = []
        bytes.reserveCapacity(count + 200)
        while bytes.count < count {
            let sentence = (0..<Int.random(in: 5...20, using: &rng))
                .map { _ in String(words.randomElement(using: &rng)!) }
                .joined(separator: " ")
            bytes.append(contentsOf: [Byte](utf8: sentence.prefix(1).uppercased() + sentence.dropFirst() + ". "))
        }
        return Array(bytes.prefix(count))
    }
}
