extension RFC_1951.HuffmanTree {
    struct TreeNode: Sendable {
        var children: (left: Int, right: Int)
        var isLeaf: Bool
        var symbol: UInt16
    }
}
