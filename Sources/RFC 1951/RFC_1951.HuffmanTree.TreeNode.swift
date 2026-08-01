// RFC_1951.HuffmanTree.TreeNode.swift

extension RFC_1951.HuffmanTree {
    struct TreeNode: Sendable {
        var children: (left: Int, right: Int)  // -1 = invalid, >= 0 = next node or symbol
        var isLeaf: Bool
        var symbol: UInt16
    }
}
