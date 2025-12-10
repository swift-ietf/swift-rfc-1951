// RFC_1951.Decompress.swift

extension RFC_1951 {
    /// Decompress DEFLATE-compressed data
    ///
    /// - Parameters:
    ///   - input: The compressed data
    ///   - output: Buffer to append decompressed data to
    /// - Throws: `Error` if the data is invalid or corrupted
    ///
    /// ## Example
    ///
    /// ```swift
    /// var decompressed: [UInt8] = []
    /// try RFC_1951.decompress(compressed, into: &decompressed)
    /// let text = String(decoding: decompressed, as: UTF8.self)
    /// ```
    public static func decompress<Input, Output>(
        _ input: Input,
        into output: inout Output
    ) throws(Error) where Input: Collection, Input.Element == UInt8, Output: RangeReplaceableCollection, Output.Element == UInt8 {
        guard !input.isEmpty else {
            throw .empty
        }

        var reader = BitReader(input)

        // Decode blocks until we hit a final block
        var isFinal = false
        while !isFinal {
            isFinal = try decodeBlock(from: &reader, into: &output)
        }
    }

    /// Convenience: decompress and return new array
    ///
    /// - Parameter input: The compressed data
    /// - Returns: Decompressed data
    /// - Throws: `Error` if the data is invalid or corrupted
    ///
    /// ## Example
    ///
    /// ```swift
    /// let decompressed = try RFC_1951.decompress(compressed)
    /// ```
    public static func decompress<Bytes>(
        _ input: Bytes
    ) throws(Error) -> [UInt8] where Bytes: Collection, Bytes.Element == UInt8 {
        var output: [UInt8] = []
        try decompress(input, into: &output)
        return output
    }
}

// MARK: - Raw DEFLATE API

extension RFC_1951 {
    /// Decompress raw DEFLATE data (no ZLIB header/trailer)
    ///
    /// Use this for contexts that use raw DEFLATE streams without
    /// ZLIB wrapping, such as PNG image data.
    ///
    /// - Parameters:
    ///   - input: The compressed data
    ///   - output: Buffer to append decompressed data to
    /// - Throws: `Error` if the data is invalid or corrupted
    public static func decompressRaw<Input, Output>(
        _ input: Input,
        into output: inout Output
    ) throws(Error) where Input: Collection, Input.Element == UInt8, Output: RangeReplaceableCollection, Output.Element == UInt8 {
        // Raw DEFLATE is the same as decompress - ZLIB unwrapping is done by RFC 1950
        try decompress(input, into: &output)
    }

    /// Convenience: raw decompress and return new array
    public static func decompressRaw<Bytes>(
        _ input: Bytes
    ) throws(Error) -> [UInt8] where Bytes: Collection, Bytes.Element == UInt8 {
        try decompress(input)
    }
}
