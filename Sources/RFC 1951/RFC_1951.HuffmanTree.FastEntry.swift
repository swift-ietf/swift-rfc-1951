// RFC_1951.HuffmanTree.FastEntry.swift

extension RFC_1951.HuffmanTree {
    struct FastEntry: Sendable {
        var symbol: UInt16  // Decoded symbol
        var length: UInt8  // Code length (0 = need tree lookup)
    }
}
