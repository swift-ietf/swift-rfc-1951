// RFC_1951.Level.swift

extension RFC_1951 {
    /// Compression level for DEFLATE encoding
    ///
    /// Higher levels produce smaller output but take longer to compress.
    /// Decompression speed is not affected by compression level.
    ///
    /// ## Example
    ///
    /// ```swift
    /// var output: [UInt8] = []
    /// RFC_1951.compress(data, into: &output, level: .best)
    /// ```
    public enum Level: Int, Sendable, Hashable, Codable, CaseIterable {
        /// No compression (stored blocks only)
        ///
        /// Output may be larger than input due to block headers.
        case none = 0

        /// Fast compression with minimal CPU usage
        ///
        /// Uses shorter search windows and simpler heuristics.
        case fast = 1

        /// Balanced compression (default)
        ///
        /// Good tradeoff between compression ratio and speed.
        case balanced = 5

        /// Best compression ratio
        ///
        /// Maximum effort to find repeated sequences.
        case best = 9
    }
}
