// RFC_1951.swift

/// RFC 1951: DEFLATE Compressed Data Format Specification version 1.3
///
/// DEFLATE is a lossless compressed data format that combines LZ77 compression
/// with Huffman coding. It is used as the compression method in gzip, PNG, ZIP,
/// and many other formats.
///
/// ## Key Types
///
/// - ``Level``: Compression level (none, fast, balanced, best)
///
/// ## Example
///
/// ```swift
/// // Compress data
/// var compressed: [UInt8] = []
/// RFC_1951.compress(input, into: &compressed)
///
/// // Decompress data
/// var decompressed: [UInt8] = []
/// try RFC_1951.decompress(compressed, into: &decompressed)
/// ```
///
/// ## See Also
///
/// - [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951)
public enum RFC_1951 {}
