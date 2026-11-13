# swift-rfc-1951

Use this package when you need to compress or decompress raw DEFLATE data, as found inside ZIP entries. Start from `RFC_1951.compress(_:level:)` and `RFC_1951.decompress(_:)`. If the data carries the zlib header and Adler-32 checksum, use swift-rfc-1950.

## Laws

- Output is raw DEFLATE with no header or checksum. `RFC_1951.compressRaw(_:level:)` and `RFC_1951.decompressRaw(_:)` give exactly the same results as `RFC_1951.compress(_:level:)` and `RFC_1951.decompress(_:)`.
- `RFC_1951.compress(_:into:level:)` appends to the buffer and leaves its existing bytes in place.
- Empty input compresses to a single empty stored block, so the output is never empty. Decompressing empty input fails with `RFC_1951.Error.empty`.
- The compressor works in 32 KiB chunks. Each chunk becomes its own block, and back-references never reach into an earlier chunk. A block is written either stored or with the fixed Huffman code, whichever is estimated to be smaller. Dynamic Huffman blocks are never written, so output is often larger than zlib's.
- `RFC_1951.Level.none` writes only stored blocks of up to 65,535 bytes. The other levels differ only in how long the match search runs before it accepts a match, and all of them decompress to the input.
- The decompressor reads stored, fixed Huffman and dynamic Huffman blocks, so it reads streams written by zlib. Input that ends before the final block fails. Decoding stops at the final block and ignores any bytes after it.
- Decompression has no limit on output size.
- Decompression reads codes through lookup tables and copies matches a word at a time. It holds the input, the output and one output buffer that grows by doubling, so peak memory is up to three times the output.
- Compression spends its time in the match search, so its speed depends on the level and the data.
- Non-contiguous input is copied into an array once before decoding.
- `swift test -c release -Xswiftc -enable-testing --filter Throughput` prints compression and decompression throughput for 8 MB inputs on the machine at hand.
