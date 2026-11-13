public import Byte

extension RFC_1951 {

    public static func decompress<Input, Output>(
        _ input: Input,
        into output: inout Output
    ) throws(Error)
    where
        Input: Swift::Collection,
        Input.Element == Byte,
        Output: RangeReplaceableCollection,
        Output.Element == Byte
    {
        guard !input.isEmpty else {
            throw .empty
        }

        var window = Window(capacity: input.count * 4)
        defer { window.deallocate() }
        let outcome =
            input.withContiguousStorageIfAvailable { bytes in
                Result { () throws(Error) in
                    try unsafe inflate(UnsafeRawBufferPointer(bytes), into: &window)
                }
            }
            ?? Array(input).withUnsafeBytes { bytes in
                Result { () throws(Error) in
                    try unsafe inflate(bytes, into: &window)
                }
            }
        window.append(to: &output)
        try outcome.get()
    }

    private static func inflate(
        _ bytes: UnsafeRawBufferPointer,
        into window: inout Window
    ) throws(Error) {
        var reader = unsafe BitReader(bytes)
        var isFinal = false
        while !isFinal {
            isFinal = try decodeBlock(from: &reader, into: &window)
        }
    }

    public static func decompress<Bytes>(
        _ input: Bytes
    ) throws(Error) -> [Byte] where Bytes: Swift::Collection, Bytes.Element == Byte {
        var output: [Byte] = []
        try decompress(input, into: &output)
        return output
    }
}

extension RFC_1951 {

    public static func decompressRaw<Input, Output>(
        _ input: Input,
        into output: inout Output
    ) throws(Error)
    where
        Input: Swift::Collection,
        Input.Element == Byte,
        Output: RangeReplaceableCollection,
        Output.Element == Byte
    {

        try decompress(input, into: &output)
    }

    public static func decompressRaw<Bytes>(
        _ input: Bytes
    ) throws(Error) -> [Byte] where Bytes: Swift::Collection, Bytes.Element == Byte {
        try decompress(input)
    }
}
